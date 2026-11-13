// TempoSnapshot.swift — what every tempo consumer reads (SHOW-011-R10, R11; data-model.md;
// contracts/tempo-source.md). SHOW-003, SHOW-010, UIX-005, MOD-009 and MIDI-010 read this, never
// the analysis directly. Times are monotonic nanoseconds on the analysis bus's clock.

/// Where the current tempo came from.
public enum TempoOrigin: String, Sendable, Hashable, Codable {
    /// Set by taps; stays until reset.
    case manual
    /// ANL-005's estimate with confidence of at least the rules' floor.
    case estimated
    /// No tempo.
    case none
}

/// An analysis estimate as the tempo source takes it.
public struct TempoEstimate: Sendable, Hashable, Codable {
    public var bpm: Double
    /// 0…1 (ANL-005).
    public var confidence: Double
    /// A beat's monotonic time; nil until the analysis reported a beat.
    public var beatNanoseconds: UInt64?

    public init(bpm: Double, confidence: Double, beatNanoseconds: UInt64?) {
        self.bpm = bpm
        self.confidence = confidence
        self.beatNanoseconds = beatNanoseconds
    }
}

/// The current tempo: origin, BPM, confidence and the beat grid.
public struct TempoSnapshot: Sendable, Hashable, Codable {
    public static let none = TempoSnapshot(origin: .none, bpm: nil, confidence: 0, anchorNanoseconds: nil)

    public let origin: TempoOrigin
    /// nil for `.none`.
    public let bpm: Double?
    /// 1 for manual, the estimate's for estimated, 0 for none.
    public let confidence: Double
    /// 60 s / BPM in whole nanoseconds; nil for `.none`.
    public let periodNanoseconds: UInt64?
    /// A beat of the grid (the last tap, or the analysis's latest beat); nil without phase.
    public let anchorNanoseconds: UInt64?

    init(origin: TempoOrigin, bpm: Double?, confidence: Double, anchorNanoseconds: UInt64?) {
        self.origin = origin
        self.bpm = bpm
        self.confidence = confidence
        periodNanoseconds = bpm.map { UInt64((60e9 / $0).rounded()) }
        self.anchorNanoseconds = anchorNanoseconds
    }

    /// The first beat at or after `time` (beats extend before the anchor too); nil without phase.
    public func nextBeat(atOrAfter time: UInt64) -> UInt64? {
        guard let anchor = anchorNanoseconds, let period = periodNanoseconds, period > 0 else { return nil }
        if time <= anchor {
            return anchor - (anchor - time) / period * period
        }
        let beats = (time - anchor + period - 1) / period
        return anchor + beats * period
    }

    /// The position within the current beat, 0..<1 (0 on a beat); nil without phase.
    public func beatPhase(at time: UInt64) -> Double? {
        guard let anchor = anchorNanoseconds, let period = periodNanoseconds, period > 0 else { return nil }
        let offset = time >= anchor ? (time - anchor) % period : (period - (anchor - time) % period) % period
        return Double(offset) / Double(period)
    }
}
