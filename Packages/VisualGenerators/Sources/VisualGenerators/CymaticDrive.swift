// CymaticDrive.swift — how the selected bands move VIS-019's figure (VIS-019-R3 to R5, R9; spec Clarifications Q3, Q4;
// research VIS-019-D3, D4).
//
// Per frame: the ANL-002 bands of the selected range (each sanitized: not finite or negative → 0, above 1 → 1) → the
// loudest band (lowest index on ties) and each part's loudest band (8 equal parts of the range) → the target mode: rest
// when the loudest band is below the silence floor, else the loudest band's part (1…8), kept when the current target's
// part is still above the floor and the new part is not at least `hysteresis` × louder → linear slews on the injected
// clock's step (clamped to 0…0.25 s, never backwards): each weight toward 1 (target) or 0 at `weightRate`/s, the
// amplitude toward the loudest band's level (0 in silence) at `amplitudeRise`/s up and `amplitudeFall`/s down. Reduce
// Motion (ACC-001) halves every rate. A slew lands exactly on its target, so silence reaches the rest state exactly
// within 0.5 s (1 s with Reduce Motion). The first frame after a reset only anchors the clock (and picks the target).
// No wall clock, no random source, no allocation. Plain Swift; builds on Linux.

public struct CymaticDrive: Sendable, Equatable {
    public static let silenceFloor: Float = 0.02
    public static let hysteresis: Float = 1.25
    public static let weightRate = 2.0
    public static let amplitudeRise = 4.0
    public static let amplitudeFall = 2.0
    public static let maxStep = 0.25
    public static let reduceMotionScale = 0.5
    /// The silence that always reaches rest (VIS-019 Clarifications Q4): 1 s, 2 s with Reduce Motion.
    public static func settleSeconds(reduceMotion: Bool) -> Double { reduceMotion ? 2 : 1 }

    /// Lanes 0…8: the modes' blend weights.
    public private(set) var weights: SIMD16<Float> = CymaticField.restWeights
    /// 0 = rest, 1…8 = the driven mode the weights move toward.
    public private(set) var target: Int = CymaticField.restIndex
    /// 0…1.
    public private(set) var amplitude: Float = 0
    /// The amplitude's target (the loudest selected band, 0 in silence).
    public private(set) var level: Float = 0
    /// Reduce Motion of the last frame.
    public private(set) var reduceMotion = false
    private var lastNanoseconds: UInt64?

    public init() {}

    public mutating func reset() { self = CymaticDrive() }

    /// The rest state: weight 1 on the rest mode, amplitude 0.
    public var isAtRest: Bool { weights == CymaticField.restWeights && amplitude == 0 }

    /// The selection of one frame: the target mode (0 rest, 1…8) the bands ask for and the loudest level.
    public static func select(bands: UnsafeBufferPointer<Float>, range: CymaticBandRange, current: Int) -> (target: Int, level: Float) {
        let span: Range<Int> = range.indices(count: bands.count)
        let count: Int = span.count
        guard count > 0 else { return (CymaticField.restIndex, 0) }
        let parts: Int = CymaticField.drivenCount
        var partMax = SIMD8<Float>(repeating: 0)
        var loudest: Float = -1
        var loudestPart = 0
        for i in span {
            let v: Float = CymaticField.clean(bands[i])
            let part: Int = (i - span.lowerBound) * parts / count
            if v > partMax[part] { partMax[part] = v }
            if v > loudest { loudest = v; loudestPart = part }
        }
        guard loudest >= silenceFloor else { return (CymaticField.restIndex, 0) }
        let candidate: Int = loudestPart + 1
        if current != CymaticField.restIndex, current != candidate, current <= parts {
            let held: Float = partMax[current - 1]
            if held >= silenceFloor && loudest < hysteresis * held { return (current, loudest) }
        }
        return (candidate, loudest)
    }

    static func slew(_ value: Float, to goal: Float, by step: Float) -> Float {
        let d: Float = goal - value
        if abs(d) <= step { return goal }
        return d > 0 ? value + step : value - step
    }

    /// Advances to the frame at `nanoseconds` with this frame's bands.
    public mutating func advance(bands: UnsafeBufferPointer<Float>, range: CymaticBandRange, timeNanoseconds nanoseconds: UInt64,
                                 reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        let choice: (target: Int, level: Float) = Self.select(bands: bands, range: range, current: target)
        guard let last = lastNanoseconds else {
            lastNanoseconds = nanoseconds
            target = choice.target
            level = choice.level
            return
        }
        guard nanoseconds > last else { return }   // never backwards
        lastNanoseconds = nanoseconds
        target = choice.target
        level = choice.level
        let scale: Double = reduceMotion ? Self.reduceMotionScale : 1
        let dt: Double = min(Double(nanoseconds - last) / 1e9, Self.maxStep)
        let step = Float(Self.weightRate * scale * dt)
        for k in 0..<CymaticField.modeCount {
            weights[k] = Self.slew(weights[k], to: k == target ? 1 : 0, by: step)
        }
        let rate: Double = level > amplitude ? Self.amplitudeRise : Self.amplitudeFall
        amplitude = Self.slew(amplitude, to: level, by: Float(rate * scale * dt))
    }

    /// The frame to draw (sanitized).
    public var frame: CymaticFrame { CymaticField.frame(weights: weights, amplitude: amplitude, reduceMotion: reduceMotion) }
}
