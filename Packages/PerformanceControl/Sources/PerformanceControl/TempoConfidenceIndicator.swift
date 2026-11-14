// TempoConfidenceIndicator.swift — searching, uncertain and stable tempo states over ANL-005's
// estimate (ANL-006-R1 to R7, R10; research ANL-006-D2, D3; contracts/tempo-confidence.md).
//
// * Fed the same `TempoEstimate` the tempo source gets, plus a monotonic time, on every poll.
// * `stable` only after confidence ≥ enter (0.7) with the BPM within the tolerance (3 %) of the
//   run's first BPM, continuously for the enter dwell (2 s); left only after "confidence < exit
//   (0.5)" or "BPM beyond the tolerance of the locked BPM" held for the exit dwell (1 s). A BPM
//   departure is a tempo change: `searching` (no number) while reacquiring, at most the reacquire
//   time (3 s), then `uncertain`. A confidence drop is `uncertain`. No usable estimate is
//   `searching` at once.
// * The exit threshold is ANL-005's "high" level, so input ANL-005 keeps below 0.5 (noise) can
//   never be or stay stable. The reported confidence is the input's, clamped; never raised.
// * `TempoSnapshot` (what consumers read) is not affected: this is an additional read-only value.
// No clock is read here: every time is an argument. Nothing here reaches projectM.

/// The tempo indicator's state.
public enum TempoConfidenceState: String, Sendable, Hashable, Codable {
    /// No usable estimate, or reacquiring after a tempo change; no BPM is shown.
    case searching
    /// An estimate that is not (or no longer) trusted.
    case uncertain
    /// An estimate that held one tempo with high confidence for the enter dwell.
    case stable
}

/// Thresholds and times of the indicator (research ANL-006-D2).
public struct TempoConfidenceRules: Sendable, Hashable {
    /// Enter 0.7, exit 0.5, 2 s / 1 s dwell, 3 s reacquire, 3 % tolerance, 60…200 BPM.
    public static let standard = TempoConfidenceRules()

    public var enterConfidence: Double
    public var exitConfidence: Double
    public var enterDwellNanoseconds: UInt64
    public var exitDwellNanoseconds: UInt64
    public var reacquireNanoseconds: UInt64
    /// Relative: 0.03 = 3 % of the reference BPM.
    public var bpmTolerance: Double
    public var minimumBPM: Double
    public var maximumBPM: Double

    public init(enterConfidence: Double = 0.7, exitConfidence: Double = 0.5,
                enterDwellNanoseconds: UInt64 = 2_000_000_000, exitDwellNanoseconds: UInt64 = 1_000_000_000,
                reacquireNanoseconds: UInt64 = 3_000_000_000, bpmTolerance: Double = 0.03,
                minimumBPM: Double = 60, maximumBPM: Double = 200) {
        precondition(exitConfidence >= 0 && enterConfidence > exitConfidence && enterConfidence <= 1,
                     "0 ≤ exit < enter ≤ 1 (hysteresis)")
        precondition(enterDwellNanoseconds > 0 && exitDwellNanoseconds > 0 && reacquireNanoseconds > 0, "positive times")
        precondition(bpmTolerance > 0, "a positive tolerance")
        precondition(minimumBPM > 0 && minimumBPM < maximumBPM, "0 < minimum < maximum")
        self.enterConfidence = enterConfidence
        self.exitConfidence = exitConfidence
        self.enterDwellNanoseconds = enterDwellNanoseconds
        self.exitDwellNanoseconds = exitDwellNanoseconds
        self.reacquireNanoseconds = reacquireNanoseconds
        self.bpmTolerance = bpmTolerance
        self.minimumBPM = minimumBPM
        self.maximumBPM = maximumBPM
    }
}

public struct TempoConfidenceIndicator: Sendable {
    public let rules: TempoConfidenceRules
    public private(set) var state: TempoConfidenceState = .searching
    /// The estimate's BPM while uncertain or stable; nil while searching.
    public private(set) var bpm: Double?
    /// The last usable estimate's confidence (clamped to 0…1); 0 while searching.
    public private(set) var confidence: Double = 0
    /// The BPM when stable was entered; nil when not stable.
    public private(set) var lockedBPM: Double?
    /// Transitions since creation (diagnostics and the flicker tests).
    public private(set) var stateChanges = 0

    private var runStart: UInt64?
    private var runBPM: Double = 0
    private var exitStart: UInt64?
    private var reacquireStart: UInt64?
    private var lastTime: UInt64?

    public init(rules: TempoConfidenceRules = .standard) {
        self.rules = rules
    }

    /// One poll: the analysis's estimate (nil: none) at monotonic `time`. A time earlier than the
    /// previous one counts as the previous one (no elapsed time).
    public mutating func update(_ estimate: TempoEstimate?, at time: UInt64) {
        let now: UInt64 = max(time, lastTime ?? time)
        lastTime = now
        guard let estimate, isUsable(estimate) else {
            enter(.searching)
            clearTracking()
            reacquireStart = nil
            return
        }
        let value: Double = min(1, max(0, estimate.confidence))
        confidence = value
        if state == .stable {
            updateStable(bpm: estimate.bpm, confidence: value, now: now)
        } else {
            updateUnlocked(bpm: estimate.bpm, confidence: value, now: now)
        }
    }

    /// Back to searching (the analysis stopped or restarted); `stateChanges` keeps counting.
    public mutating func reset() {
        enter(.searching)
        clearTracking()
        reacquireStart = nil
        lastTime = nil
    }

    // MARK: Internals

    private func isUsable(_ estimate: TempoEstimate) -> Bool {
        guard estimate.bpm.isFinite, estimate.confidence.isFinite else { return false }
        return estimate.bpm >= rules.minimumBPM && estimate.bpm <= rules.maximumBPM
    }

    private func isWithin(_ value: Double, of reference: Double) -> Bool {
        let limit: Double = rules.bpmTolerance * reference
        return abs(value - reference) <= limit
    }

    private static func elapsed(from start: UInt64, to now: UInt64) -> UInt64 {
        now >= start ? now - start : 0
    }

    private mutating func clearTracking() {
        bpm = nil
        confidence = 0
        lockedBPM = nil
        runStart = nil
        exitStart = nil
    }

    private mutating func enter(_ next: TempoConfidenceState) {
        guard next != state else { return }
        state = next
        stateChanges += 1
    }

    /// Starts, keeps or clears the run of confident estimates at one tempo.
    private mutating func considerRun(bpm value: Double, confidence: Double, now: UInt64) {
        guard confidence >= rules.enterConfidence else {
            runStart = nil
            return
        }
        if runStart != nil, isWithin(value, of: runBPM) { return }
        runStart = now
        runBPM = value
    }

    private mutating func updateStable(bpm value: Double, confidence: Double, now: UInt64) {
        let locked: Double = lockedBPM ?? value
        let departed: Bool = !isWithin(value, of: locked)
        // While the exit dwell runs after a departure, the readout keeps the last BPM within the
        // tolerance: a new tempo is never shown as stable before it has earned it.
        if !departed { bpm = value }
        let weak: Bool = confidence < rules.exitConfidence
        guard departed || weak else {
            exitStart = nil
            return
        }
        let start: UInt64 = exitStart ?? now
        exitStart = start
        guard Self.elapsed(from: start, to: now) >= rules.exitDwellNanoseconds else { return }
        exitStart = nil
        lockedBPM = nil
        runStart = nil
        if departed {
            enter(.searching)
            reacquireStart = now
            bpm = nil
        } else {
            enter(.uncertain)
        }
        considerRun(bpm: value, confidence: confidence, now: now)
    }

    private mutating func updateUnlocked(bpm value: Double, confidence: Double, now: UInt64) {
        considerRun(bpm: value, confidence: confidence, now: now)
        if let start = runStart, Self.elapsed(from: start, to: now) >= rules.enterDwellNanoseconds {
            enter(.stable)
            lockedBPM = value
            runStart = nil
            reacquireStart = nil
            exitStart = nil
            bpm = value
            return
        }
        if state == .searching {
            if let start = reacquireStart {
                if Self.elapsed(from: start, to: now) >= rules.reacquireNanoseconds {
                    enter(.uncertain)
                    reacquireStart = nil
                }
            } else {
                enter(.uncertain)
            }
        }
        bpm = state == .searching ? nil : value
    }
}

/// What the tempo readout shows: a manual tempo wins over every analysis state (ANL-006-R7, R8).
public enum TempoReadout: Sendable, Hashable {
    case manual(bpm: Double)
    case stable(bpm: Double)
    case uncertain(bpm: Double)
    case searching

    public init(snapshot: TempoSnapshot, indicator: TempoConfidenceIndicator) {
        if snapshot.origin == .manual, let bpm = snapshot.bpm {
            self = .manual(bpm: bpm)
            return
        }
        guard let bpm = indicator.bpm else {
            self = .searching
            return
        }
        switch indicator.state {
        case .stable: self = .stable(bpm: bpm)
        case .uncertain: self = .uncertain(bpm: bpm)
        case .searching: self = .searching
        }
    }

    /// The BPM shown, if any.
    public var bpm: Double? {
        switch self {
        case .manual(let bpm), .stable(let bpm), .uncertain(let bpm): bpm
        case .searching: nil
        }
    }
}
