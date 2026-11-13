// WaveformTrigger.swift — the oscilloscope's trigger stabilization (VIS-003-R3 to R6; research
// VIS-003-D2; specs/083-vis-003-waveform-oscilloscope/contracts/waveform-oscilloscope.md C1).
//
// Input: a history of mono samples, oldest first, and a window length W. Output: where the displayed
// window starts (a fractional history index) so a periodic signal draws at the same phase every frame.
// 1. Level = (min + max)/2 of the history; range = max − min. Silence (range < 0.002) free-runs.
// 2. Scan positions 1…H − W (every window starting there fits) for rising crossings with hysteresis:
//    armed once a sample is below level − 0.05·range, a crossing is the first sample ≥ level after
//    that, located between the two samples by linear interpolation; then disarmed. The newest 32 are
//    kept (a ring). No crossing free-runs.
// 3. Periodicity: for k = 1…4 (with at least k + 2 crossings) the grouped intervals c[i + k] − c[i]
//    must have a standard deviation ≤ 0.1 × their mean for some k (a wave with k rising crossings
//    per period passes at k; white noise fails every k), else the signal is aperiodic and free-runs.
//    With fewer than 3 crossings periodicity cannot be judged and the crossings are used.
// 4. Choice: with a 64-point reference of the previous frame's window (same W), each crossing's
//    window is resampled at 64 points and scored by its sum of squared differences from the
//    reference; the newest crossing within 1.05 × best + 1e-4 wins. Without a reference, the newest.
//    The chosen window's 64 points become the next reference. Free-run shows the newest window
//    (start = H − W) and clears the reference.
// Samples are sanitized (NaN, ±∞ → 0). Real-time safety (Constitution VII): every buffer is allocated
// in `init`; `locate` only reads its input and writes that storage. Not Sendable: one owner.

/// Why the trigger free-runs.
public enum WaveformFreeRunReason: String, Sendable, Hashable {
    case silence
    case noCrossing
    case aperiodic
}

public enum WaveformTriggerMode: Sendable, Hashable {
    case triggered
    case freeRun(WaveformFreeRunReason)
}

public struct WaveformTriggerResult: Sendable, Equatable {
    /// Fractional history index of the window's first sample (0…H − W).
    public var start: Double
    public var mode: WaveformTriggerMode
    /// Qualifying crossings found where a window fits (at most `maximumCrossings` are kept).
    public var crossingCount: Int
    /// Samples per period (mean grouped crossing interval), when the signal was judged periodic.
    public var periodSamples: Double?

    public init(start: Double, mode: WaveformTriggerMode, crossingCount: Int, periodSamples: Double?) {
        self.start = start
        self.mode = mode
        self.crossingCount = crossingCount
        self.periodSamples = periodSamples
    }
}

public final class WaveformTrigger {
    public static let maximumCrossings = 32
    public static let referencePoints = 64
    /// Peak-to-peak range below which the signal is silence.
    public static let silenceRange: Float = 0.002
    /// Hysteresis as a fraction of the range.
    public static let hysteresisFraction: Float = 0.05
    /// Largest grouped-interval spread (standard deviation / mean) of a periodic signal.
    public static let periodicSpread = 0.1
    /// Largest crossings-per-period grouping tried.
    public static let maximumGrouping = 4
    /// Scores within `scoreTolerance` × best + `scoreFloor` count as equal (the newest wins).
    public static let scoreTolerance = 1.05
    public static let scoreFloor = 1e-4

    private let crossings: UnsafeMutablePointer<Double>
    private let reference: UnsafeMutablePointer<Float>
    private var referenceWindow = 0
    public private(set) var hasReference = false

    public init() {
        crossings = .allocate(capacity: Self.maximumCrossings)
        crossings.initialize(repeating: 0, count: Self.maximumCrossings)
        reference = .allocate(capacity: Self.referencePoints)
        reference.initialize(repeating: 0, count: Self.referencePoints)
    }

    deinit {
        crossings.deinitialize(count: Self.maximumCrossings); crossings.deallocate()
        reference.deinitialize(count: Self.referencePoints); reference.deallocate()
    }

    /// Forgets the previous frame's window (a new picture starts).
    public func reset() {
        hasReference = false
        referenceWindow = 0
    }

    // Storage introspection for the allocation tests (VIS-003-S3).
    var crossingCapacity: Int { Self.maximumCrossings }
    var referenceCapacity: Int { Self.referencePoints }
    var storageAddresses: [UInt] { [UInt(bitPattern: crossings), UInt(bitPattern: reference)] }

    @inline(__always)
    private static func sample(_ history: UnsafeBufferPointer<Float>, _ i: Int) -> Float {
        let v = history[i]
        return v.isFinite ? v : 0
    }

    /// The history value at fractional index `q` (linear interpolation, clamped to the history).
    @inline(__always)
    static func interpolate(_ history: UnsafeBufferPointer<Float>, _ q: Double) -> Float {
        let last = history.count - 1
        guard last > 0 else { return last == 0 ? sample(history, 0) : 0 }
        let clamped: Double = min(max(q, 0), Double(last))
        let i0 = min(Int(clamped), last - 1)
        let f = Float(clamped - Double(i0))
        return sample(history, i0) * (1 - f) + sample(history, i0 + 1) * f
    }

    /// The window start for `windowSamples` samples of `history` (oldest first). No allocation.
    public func locate(in history: UnsafeBufferPointer<Float>, windowSamples: Int) -> WaveformTriggerResult {
        let h = history.count
        let w = min(max(windowSamples, 2), max(h, 2))
        let newest = Double(max(h - w, 0))
        func freeRun(_ reason: WaveformFreeRunReason, count: Int) -> WaveformTriggerResult {
            hasReference = false
            return WaveformTriggerResult(start: newest, mode: .freeRun(reason), crossingCount: count, periodSamples: nil)
        }
        guard h >= 2 else { return freeRun(.silence, count: 0) }

        var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
        for i in 0..<h {
            let v = Self.sample(history, i)
            low = min(low, v)
            high = max(high, v)
        }
        let range = high - low
        guard range >= Self.silenceRange else { return freeRun(.silence, count: 0) }
        let level = (low + high) / 2
        let arm = level - Self.hysteresisFraction * range

        // Rising crossings with hysteresis whose window fits: the newest `maximumCrossings` in a ring.
        let lastStart = h - w
        var total = 0
        var armed = false
        if lastStart >= 1 {
            var previous = Self.sample(history, 0)
            armed = previous < arm
            for i in 1...lastStart {
                let v = Self.sample(history, i)
                if armed && previous < level && v >= level {
                    let fraction: Float = (level - previous) / (v - previous)
                    crossings[total % Self.maximumCrossings] = Double(i - 1) + Double(fraction)
                    total += 1
                    armed = false
                } else if v < arm {
                    armed = true
                }
                previous = v
            }
        }
        guard total > 0 else { return freeRun(.noCrossing, count: 0) }
        let kept = min(total, Self.maximumCrossings)
        let first = total - kept   // ring index of the oldest kept crossing
        @inline(__always) func crossing(_ n: Int) -> Double { crossings[(first + n) % Self.maximumCrossings] }

        // Periodicity (groupings 1…4).
        var period: Double?
        if kept >= 3 {
            for k in 1...Self.maximumGrouping where kept >= k + 2 {
                let count = kept - k
                var sum = 0.0, squares = 0.0
                for n in 0..<count {
                    let d: Double = crossing(n + k) - crossing(n)
                    sum += d
                    squares += d * d
                }
                let mean: Double = sum / Double(count)
                let variance: Double = max(squares / Double(count) - mean * mean, 0)
                if mean > 0 && variance.squareRoot() <= Self.periodicSpread * mean {
                    period = mean
                    break
                }
            }
            guard period != nil else { return freeRun(.aperiodic, count: total) }
        } else if kept == 2 {
            period = crossing(1) - crossing(0)
        }

        // Choice: the newest crossing matching the previous window.
        let step: Double = Double(w - 1) / Double(Self.referencePoints - 1)
        var chosen = crossing(kept - 1)
        if hasReference && referenceWindow == w {
            var best = Double.greatestFiniteMagnitude
            for n in 0..<kept { best = min(best, score(history, start: crossing(n), step: step)) }
            let limit: Double = best * Self.scoreTolerance + Self.scoreFloor
            for n in stride(from: kept - 1, through: 0, by: -1) where score(history, start: crossing(n), step: step) <= limit {
                chosen = crossing(n)
                break
            }
        }
        for j in 0..<Self.referencePoints {
            reference[j] = Self.interpolate(history, chosen + Double(j) * step)
        }
        referenceWindow = w
        hasReference = true
        return WaveformTriggerResult(start: chosen, mode: .triggered, crossingCount: total, periodSamples: period)
    }

    /// Sum of squared differences between the window at `start` (64 points) and the reference.
    private func score(_ history: UnsafeBufferPointer<Float>, start: Double, step: Double) -> Double {
        var sum = 0.0
        for j in 0..<Self.referencePoints {
            let d = Double(Self.interpolate(history, start + Double(j) * step) - reference[j])
            sum += d * d
        }
        return sum
    }
}
