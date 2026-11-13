// TapTempoRules.swift — the limits of tap tempo (SHOW-011-R2, R3, R5, R6, R9; research
// SHOW-011-D1, D2; contracts/tempo-source.md).

/// The rules a `TempoSource` applies to taps and estimates.
public struct TapTempoRules: Sendable, Hashable, Codable {
    /// 4 taps, 60-200 BPM (ANL-005's range), a 2 s pause, the last 8 taps, confidence 0.5.
    public static let standard = TapTempoRules()

    /// The accepted tap that sets a manual tempo (≥ 2).
    public var tapsToEstablish: Int
    public var minimumBPM: Double
    public var maximumBPM: Double
    /// An interval longer than this starts a new sequence without feedback.
    public var pauseNanoseconds: UInt64
    /// Taps the tempo fit uses (≥ `tapsToEstablish`).
    public var maximumTaps: Int
    /// An estimate counts from this confidence (ANL-005's "high").
    public var minimumEstimateConfidence: Double

    public init(tapsToEstablish: Int = 4, minimumBPM: Double = 60, maximumBPM: Double = 200,
                pauseNanoseconds: UInt64 = 2_000_000_000, maximumTaps: Int = 8, minimumEstimateConfidence: Double = 0.5) {
        precondition(tapsToEstablish >= 2, "two taps make the first interval")
        precondition(minimumBPM > 0 && minimumBPM < maximumBPM, "0 < minimum < maximum")
        precondition(maximumTaps >= tapsToEstablish, "the fit window holds the establishing taps")
        self.tapsToEstablish = tapsToEstablish
        self.minimumBPM = minimumBPM
        self.maximumBPM = maximumBPM
        self.pauseNanoseconds = pauseNanoseconds
        self.maximumTaps = maximumTaps
        self.minimumEstimateConfidence = minimumEstimateConfidence
    }

    /// Intervals shorter than this are too fast (300 ms at 200 BPM).
    public var shortestIntervalNanoseconds: UInt64 { UInt64((60e9 / maximumBPM).rounded()) }
    /// Intervals longer than this (and not a pause) are too slow (1 s at 60 BPM).
    public var longestIntervalNanoseconds: UInt64 { UInt64((60e9 / minimumBPM).rounded()) }

    func contains(bpm: Double) -> Bool { bpm >= minimumBPM && bpm <= maximumBPM }
}
