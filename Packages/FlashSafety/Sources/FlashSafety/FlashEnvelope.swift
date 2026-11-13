// FlashEnvelope.swift — the strobe safety envelope's decision rule (FX-019-R1, R5, R6, R8, R10,
// R11, R13; ADR-0011 decision 3; research FX-019-D2; data-model.md).
//
// Per frame, for each of the 17 areas and both signals:
// 1. the clock advances by the clamped frame time (every stored transition age grows);
// 2. a ceiling for this frame's value: the previous shown value + rate × dt when a rise rate is set,
//    and — when the current leg is not rising and more than budget − 2 transitions are younger than
//    the window — the running minimum + threshold − margin (no new rise transition);
// 3. the gain g ∈ 0…1 is the largest that keeps every area's signals within their ceilings;
// 4. the values shown at g are committed: the hysteresis detector records a transition when a value
//    reverses by the threshold from the running extreme of the previous leg.
// Why the budget holds: transitions alternate; a rise is allowed only with at most budget − 2 in the
// window, so the fall that may follow it (never held, since the envelope only dims) still fits.
//
// The GLSL port in Packages/Rendering/Sources/CFlashLimiter/FlashLimiter.c runs the same rule on
// projectM frames; keep the two in step (GPU tests compare them).
//
// Real-time safety: all state is allocated in `init`; `gain` allocates nothing, takes no lock and
// does no I/O. Deterministic. Not Sendable: one thread drives an envelope.

public final class FlashEnvelope {
    public static let bisectionSteps = 24
    static let trackCount = FlashZones.count * 2
    static let ageSlots = FlashEnvelopeConfiguration.maxTransitionBudget
    /// A transition this close to the window's length still counts (conservative against float
    /// accumulation of frame times; `FlashAnalysis` uses a smaller tolerance).
    static let windowTolerance = 1e-6

    enum Direction: UInt8 { case none, rising, falling }

    struct Track {
        var initialized = false
        var last = 0.0
        var low = 0.0
        var high = 0.0
        var direction = Direction.none
    }

    private let tracks: UnsafeMutablePointer<Track>
    private let ages: UnsafeMutablePointer<Double>
    private let ceilings: UnsafeMutablePointer<Double>
    private let probe: UnsafeMutableBufferPointer<FlashLevels>
    private let best: UnsafeMutableBufferPointer<FlashLevels>
    /// The gain of the last frame (1 when nothing was limited).
    public private(set) var lastGain: Float = 1

    public init() {
        tracks = .allocate(capacity: Self.trackCount)
        tracks.initialize(repeating: Track(), count: Self.trackCount)
        ages = .allocate(capacity: Self.trackCount * Self.ageSlots)
        ages.initialize(repeating: .infinity, count: Self.trackCount * Self.ageSlots)
        ceilings = .allocate(capacity: Self.trackCount)
        ceilings.initialize(repeating: .infinity, count: Self.trackCount)
        probe = .allocate(capacity: FlashZones.count)
        probe.initialize(repeating: .zero)
        best = .allocate(capacity: FlashZones.count)
        best.initialize(repeating: .zero)
    }

    deinit {
        tracks.deinitialize(count: Self.trackCount)
        tracks.deallocate()
        ages.deinitialize(count: Self.trackCount * Self.ageSlots)
        ages.deallocate()
        ceilings.deinitialize(count: Self.trackCount)
        ceilings.deallocate()
        probe.deallocate()
        best.deallocate()
    }

    /// Forgets all history: the next frame is shown as it is (a new visual; FX-019-R11).
    public func reset() {
        for i in 0..<Self.trackCount { tracks[i] = Track() }
        for i in 0..<(Self.trackCount * Self.ageSlots) { ages[i] = .infinity }
        lastGain = 1
    }

    /// The values committed for `zone` by the last frame (tests, diagnostics).
    public func shown(zone: Int) -> FlashLevels {
        FlashLevels(luminance: tracks[zone * 2].last, redness: tracks[zone * 2 + 1].last)
    }

    /// Transitions of `zone`'s `signal` younger than the window after the last frame (tests).
    public func transitionsInWindow(zone: Int, signal: FlashSignal, configuration: FlashEnvelopeConfiguration) -> Int {
        count(track: zone * 2 + signal.rawValue, window: configuration.window)
    }

    // MARK: - Gain

    /// The gain for a frame whose levels scale linearly with it (`inputs` = the 17 areas at gain 1;
    /// projectM frames, and the reference for the GPU port): the closed form min(ceiling / level).
    public func gain(inputs: UnsafeBufferPointer<FlashLevels>, frameTime: Double,
                     configuration: FlashEnvelopeConfiguration) -> Float {
        prepare(frameTime: frameTime, configuration: configuration)
        var g = 1.0
        for z in 0..<FlashZones.count {
            let level = z < inputs.count ? Self.sanitized(inputs[z]) : .zero
            for s in FlashSignal.allCases {
                let v = level[s]
                let c = ceilings[z * 2 + s.rawValue]
                if v > c { g = min(g, max(c, 0) / v) }
            }
        }
        let gain = Self.floatAtMost(min(max(g, 0), 1))
        for z in 0..<FlashZones.count {
            let level = z < inputs.count ? Self.sanitized(inputs[z]) : .zero
            best[z] = FlashLevels(luminance: level.luminance * Double(gain), redness: level.redness * Double(gain))
        }
        commit(best, configuration: configuration)
        lastGain = gain
        return gain
    }

    /// The gain for a frame whose 17 area levels at gain g are written by `levels(g, out)`,
    /// nondecreasing in g (native visuals: a background the gain does not scale, a glow): the largest
    /// g within every ceiling, by `bisectionSteps` steps. If even g = 0 exceeds a ceiling, 0.
    public func gain(frameTime: Double, configuration: FlashEnvelopeConfiguration,
                     levels: (Float, UnsafeMutableBufferPointer<FlashLevels>) -> Void) -> Float {
        prepare(frameTime: frameTime, configuration: configuration)
        var gain: Float = 1
        evaluate(1, levels, into: best)
        if !withinCeilings(best) {
            var lo: Float = 0, hi: Float = 1
            evaluate(0, levels, into: best)
            if withinCeilings(best) {
                for _ in 0..<Self.bisectionSteps {
                    let mid = (lo + hi) / 2
                    evaluate(mid, levels, into: probe)
                    if withinCeilings(probe) {
                        lo = mid
                        for z in 0..<FlashZones.count { best[z] = probe[z] }
                    } else {
                        hi = mid
                    }
                }
            }
            gain = lo
        }
        commit(best, configuration: configuration)
        lastGain = gain
        return gain
    }

    // MARK: - Internals

    @inline(__always)
    private func evaluate(_ g: Float, _ levels: (Float, UnsafeMutableBufferPointer<FlashLevels>) -> Void,
                          into out: UnsafeMutableBufferPointer<FlashLevels>) {
        for z in 0..<FlashZones.count { out[z] = .zero }
        levels(g, out)
        for z in 0..<FlashZones.count { out[z] = Self.sanitized(out[z]) }
    }

    private func withinCeilings(_ levels: UnsafeMutableBufferPointer<FlashLevels>) -> Bool {
        for z in 0..<FlashZones.count {
            if levels[z].luminance > ceilings[z * 2] || levels[z].redness > ceilings[z * 2 + 1] { return false }
        }
        return true
    }

    @inline(__always)
    static func sanitized(_ v: Double) -> Double { v.isFinite ? max(v, 0) : 0 }

    @inline(__always)
    static func sanitized(_ l: FlashLevels) -> FlashLevels {
        FlashLevels(luminance: sanitized(l.luminance), redness: sanitized(l.redness))
    }

    /// The largest Float not above `x` (x in 0…1), so g × level never exceeds a ceiling by rounding.
    @inline(__always)
    static func floatAtMost(_ x: Double) -> Float {
        let f = Float(x)
        return Double(f) > x ? f.nextDown : f
    }

    private func count(track i: Int, window: Double) -> Int {
        var n = 0
        let base = i * Self.ageSlots
        for k in 0..<Self.ageSlots where ages[base + k] < window + Self.windowTolerance { n += 1 }
        return n
    }

    /// Steps 1 and 2: advance the clock and compute every ceiling.
    private func prepare(frameTime: Double, configuration c: FlashEnvelopeConfiguration) {
        let dt = c.clampedFrameTime(frameTime)
        for i in 0..<(Self.trackCount * Self.ageSlots) { ages[i] += dt }
        for i in 0..<Self.trackCount {
            let t = tracks[i]
            guard t.initialized else {
                ceilings[i] = .infinity
                continue
            }
            var ceiling = Double.infinity
            if let rate = c.riseRatePerSecond { ceiling = t.last + rate * dt }
            if t.direction != .rising, count(track: i, window: c.window) > c.transitionBudget - 2 {
                let threshold = c.threshold(for: FlashSignal(rawValue: i % 2)!)
                ceiling = min(ceiling, t.low + threshold - c.gateMargin)
            }
            ceilings[i] = ceiling
        }
    }

    /// Step 4: record the shown values and any transitions.
    private func commit(_ shown: UnsafeMutableBufferPointer<FlashLevels>, configuration c: FlashEnvelopeConfiguration) {
        for i in 0..<Self.trackCount {
            let v = shown[i / 2][FlashSignal(rawValue: i % 2)!]
            let threshold = c.threshold(for: FlashSignal(rawValue: i % 2)!)
            var t = tracks[i]
            var transition = false
            if !t.initialized {
                t = Track(initialized: true, last: v, low: v, high: v, direction: .none)
            } else {
                switch t.direction {
                case .none:
                    if v >= t.low + threshold {
                        t.direction = .rising; t.high = v; transition = true
                    } else if v <= t.high - threshold {
                        t.direction = .falling; t.low = v; transition = true
                    } else {
                        t.low = min(t.low, v); t.high = max(t.high, v)
                    }
                case .rising:
                    if v > t.high {
                        t.high = v
                    } else if v <= t.high - threshold {
                        t.direction = .falling; t.low = v; transition = true
                    }
                case .falling:
                    if v < t.low {
                        t.low = v
                    } else if v >= t.low + threshold {
                        t.direction = .rising; t.high = v; transition = true
                    }
                }
                t.last = v
            }
            tracks[i] = t
            if transition { record(track: i) }
        }
    }

    /// Writes age 0 into the oldest slot (an expired one when any is).
    private func record(track i: Int) {
        let base = i * Self.ageSlots
        var oldest = base
        for k in 1..<Self.ageSlots where ages[base + k] > ages[oldest] { oldest = base + k }
        ages[oldest] = 0
    }
}
