// TempoSource.swift — tap tempo over the analysis estimate (SHOW-011-R1 to R11; research
// SHOW-011-D1, D2; data-model.md; contracts/tempo-source.md).
//
// * Taps: an interval shorter than the rules' shortest (300 ms) is ignored (`tooFast`); longer than
//   the longest (1 s) and at most the pause (2 s) restarts the sequence at that tap (`tooSlow`);
//   longer than the pause restarts it silently. The `tapsToEstablish`-th accepted tap (4) sets a
//   manual tempo; later taps refine it.
// * Tempo: the period is the least-squares slope of the last `maximumTaps` (8) tap times against
//   their index; evenly spaced taps give their interval exactly and timing errors average out.
//   Accepted intervals all lie within the range, so the slope does too.
// * Phase: the manual grid's beats fall on the last accepted tap.
// * The estimate counts only with confidence ≥ the rules' floor (0.5) and a tempo in range; it
//   never overrides a manual tempo. `resetManual()` clears the override and the sequence.
// No clock is read here: every time is an argument (SHOW-011-R11).

/// What a tap did, for feedback.
public enum TapOutcome: Sendable, Hashable {
    /// Taps `taps` of `of` in the current sequence (also the first tap after a pause).
    case counting(taps: Int, of: Int)
    /// This tap set a manual tempo where there was none.
    case established(bpm: Double)
    /// This tap changed an existing manual tempo (including a new sequence's establishing tap).
    case refined(bpm: Double)
    /// Faster than the fastest tempo: the tap was ignored.
    case tooFast
    /// Slower than the slowest tempo: the sequence restarted at this tap.
    case tooSlow
}

public struct TempoSource: Sendable {
    public let rules: TapTempoRules
    private var taps: [UInt64] = []
    private var manual: (bpm: Double, anchor: UInt64)?
    private var estimate: TempoEstimate?

    public init(rules: TapTempoRules = .standard) {
        self.rules = rules
        taps.reserveCapacity(rules.maximumTaps)
    }

    /// Accepted taps in the current sequence (0 after a reset).
    public var tapsInSequence: Int { taps.count }

    public var hasManualTempo: Bool { manual != nil }

    /// The one read API (SHOW-011-R10).
    public var snapshot: TempoSnapshot {
        if let manual {
            return TempoSnapshot(origin: .manual, bpm: manual.bpm, confidence: 1, anchorNanoseconds: manual.anchor)
        }
        if let estimate, estimate.confidence >= rules.minimumEstimateConfidence, rules.contains(bpm: estimate.bpm) {
            return TempoSnapshot(origin: .estimated, bpm: estimate.bpm, confidence: estimate.confidence,
                                 anchorNanoseconds: estimate.beatNanoseconds)
        }
        return .none
    }

    /// A tap at `time` (monotonic nanoseconds, not earlier than the previous tap's).
    @discardableResult
    public mutating func tap(at time: UInt64) -> TapOutcome {
        if let last = taps.last {
            let interval = time >= last ? time - last : 0
            if interval < rules.shortestIntervalNanoseconds { return .tooFast }
            if interval > rules.pauseNanoseconds {
                taps = [time]
                return .counting(taps: 1, of: rules.tapsToEstablish)
            }
            if interval > rules.longestIntervalNanoseconds {
                taps = [time]
                return .tooSlow
            }
        }
        if taps.count == rules.maximumTaps { taps.removeFirst() }
        taps.append(time)
        guard taps.count >= rules.tapsToEstablish else {
            return .counting(taps: taps.count, of: rules.tapsToEstablish)
        }
        // A sequence that restarted keeps counting up from 1, so `taps.count` is its length.
        let bpm = 60e9 / fittedPeriod()
        let hadManual = manual != nil
        manual = (bpm, time)
        return hadManual ? .refined(bpm: bpm) : .established(bpm: bpm)
    }

    /// Clears the manual tempo and the tap sequence (SHOW-011-R8).
    public mutating func resetManual() {
        manual = nil
        taps.removeAll(keepingCapacity: true)
    }

    /// The analysis's current estimate; nil when it has none.
    public mutating func updateEstimate(_ estimate: TempoEstimate?) {
        self.estimate = estimate
    }

    /// Least-squares slope of tap time against tap index (research SHOW-011-D1).
    private func fittedPeriod() -> Double {
        let n = Double(taps.count)
        let meanIndex = (n - 1) / 2
        let origin = taps[0]
        var meanTime = 0.0
        for t in taps { meanTime += Double(t - origin) }
        meanTime /= n
        var numerator = 0.0
        var denominator = 0.0
        for (i, t) in taps.enumerated() {
            let x = Double(i) - meanIndex
            numerator += x * (Double(t - origin) - meanTime)
            denominator += x * x
        }
        return numerator / denominator
    }
}
