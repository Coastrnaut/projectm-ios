// BeatTrackerConfiguration.swift — parameters of the adaptive beat tracker and the values it reports
// (ANL-005-R6, R10, R14; data-model.md; defaults from research ANL-005-D5). Invalid configurations
// cannot be constructed.

public enum BeatTrackerConfigurationError: Error, Equatable, Sendable {
    /// Finite and at least `BandLayout.minimumSampleRate` (8,000 Hz).
    case invalidSampleRate(Double)
    /// 30 ≤ minimum, maximum ≤ 300, maximum ≥ 1.5 × minimum (minimum, maximum).
    case invalidTempoRange(Double, Double)
    /// Within the tempo range.
    case invalidPreferredTempo(Double)
    /// 2…16 s.
    case invalidWindow(Double)
    /// 0.005…0.1 s.
    case invalidTimingTolerance(Double)
    /// 1…16 s and longer than 1.5 periods of the minimum tempo.
    case invalidSilenceTimeout(Double)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        func same(_ a: Double, _ b: Double) -> Bool { a == b || (a.isNaN && b.isNaN) }
        switch (lhs, rhs) {
        case let (.invalidSampleRate(a), .invalidSampleRate(b)): return same(a, b)
        case let (.invalidTempoRange(a, c), .invalidTempoRange(b, d)): return same(a, b) && same(c, d)
        case let (.invalidPreferredTempo(a), .invalidPreferredTempo(b)): return same(a, b)
        case let (.invalidWindow(a), .invalidWindow(b)): return same(a, b)
        case let (.invalidTimingTolerance(a), .invalidTimingTolerance(b)): return same(a, b)
        case let (.invalidSilenceTimeout(a), .invalidSilenceTimeout(b)): return same(a, b)
        default: return false
        }
    }
}

public struct BeatTrackerConfiguration: Sendable, Hashable {
    /// Onsets kept in the history at most (bounds the per-onset work).
    public static let maximumOnsets = 64
    /// Resolution of the tempo score grid.
    public static let gridStepBPM = 0.25
    /// Pairs of onsets further apart than this do not vote.
    public static let maximumLagSeconds = 4.0
    /// Multiples n = 1…harmonics of the period an interval votes for.
    public static let harmonics = 4
    /// Recency weight 2^(−age / half-life).
    public static let recencyHalfLifeSeconds = 2.0
    /// A tracked tempo is kept while its score is at least this share of the best.
    public static let hysteresis = 0.9
    /// Distinct matched beats an estimate needs.
    public static let minimumMatchedBeats = 4

    /// The defaults at 44,100 Hz, without a throwing call.
    public static let standard = BeatTrackerConfiguration(
        valid: 44_100, minimumBPM: 60, maximumBPM: 200, preferredBPM: 120, windowSeconds: 6,
        timingToleranceSeconds: 0.035, silenceTimeoutSeconds: 4)

    public let sampleRate: Double
    public let minimumBPM: Double
    public let maximumBPM: Double
    /// Centre of the mild tempo preference (decides near-ties between octaves).
    public let preferredBPM: Double
    /// Onsets older than this (behind the newest onset) leave the history.
    public let windowSeconds: Double
    /// How far an onset may lie from a grid beat and still count as on it (τ).
    public let timingToleranceSeconds: Double
    /// With no matched onset for this long the estimate is dropped ("no tempo").
    public let silenceTimeoutSeconds: Double

    public init(sampleRate: Double = 44_100, minimumBPM: Double = 60, maximumBPM: Double = 200,
                preferredBPM: Double = 120, windowSeconds: Double = 6, timingToleranceSeconds: Double = 0.035,
                silenceTimeoutSeconds: Double = 4) throws(BeatTrackerConfigurationError) {
        guard sampleRate.isFinite, sampleRate >= BandLayout.minimumSampleRate else { throw .invalidSampleRate(sampleRate) }
        guard minimumBPM >= 30, maximumBPM <= 300, maximumBPM >= 1.5 * minimumBPM else {
            throw .invalidTempoRange(minimumBPM, maximumBPM)
        }
        guard preferredBPM >= minimumBPM, preferredBPM <= maximumBPM else { throw .invalidPreferredTempo(preferredBPM) }
        guard windowSeconds >= 2, windowSeconds <= 16 else { throw .invalidWindow(windowSeconds) }
        guard timingToleranceSeconds >= 0.005, timingToleranceSeconds <= 0.1 else {
            throw .invalidTimingTolerance(timingToleranceSeconds)
        }
        guard silenceTimeoutSeconds >= 1, silenceTimeoutSeconds <= 16, silenceTimeoutSeconds > 1.5 * 60 / minimumBPM else {
            throw .invalidSilenceTimeout(silenceTimeoutSeconds)
        }
        self.init(valid: sampleRate, minimumBPM: minimumBPM, maximumBPM: maximumBPM, preferredBPM: preferredBPM,
                  windowSeconds: windowSeconds, timingToleranceSeconds: timingToleranceSeconds,
                  silenceTimeoutSeconds: silenceTimeoutSeconds)
    }

    private init(valid sampleRate: Double, minimumBPM: Double, maximumBPM: Double, preferredBPM: Double,
                 windowSeconds: Double, timingToleranceSeconds: Double, silenceTimeoutSeconds: Double) {
        self.sampleRate = sampleRate
        self.minimumBPM = minimumBPM
        self.maximumBPM = maximumBPM
        self.preferredBPM = preferredBPM
        self.windowSeconds = windowSeconds
        self.timingToleranceSeconds = timingToleranceSeconds
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
    }

    /// Bins of the tempo score grid: (maximum − minimum) / step + 1.
    public var gridBins: Int { Int(((maximumBPM - minimumBPM) / BeatTrackerConfiguration.gridStepBPM).rounded(.down)) + 1 }
}

/// The tracker's current tempo and beat grid (ANL-005-R6, R7). Times are on the stream's sample clock.
public struct BeatEstimate: Sendable, Hashable {
    public let bpm: Double
    /// Beat period in samples (fractional).
    public let periodSamples: Double
    /// A beat time of the fitted grid: the one nearest the last matched onset.
    public let anchorSample: Double
    /// The first grid beat at or after `position`, rounded to a sample.
    public let nextBeatSample: Int64
    /// precision × coverage × support × freshness, 0…1.
    public let confidence: Double
    /// Share of the window's onsets that lie on the grid.
    public let precision: Double
    /// Share of the grid beats between the window's first and last onset that have an onset.
    public let coverage: Double
    /// clamp((matched beats − 4) / 4, 0, 1).
    public let support: Double
    /// 1 up to 1.5 periods after the last matched onset, then linearly to 0 at the silence timeout.
    public let freshness: Double
    /// Distinct grid beats with an onset (at least 4).
    public let matchedBeats: Int
    public let onsetsInWindow: Int
    public let sampleRate: Double
    /// The stream position this estimate describes.
    public let position: Int64

    public var seconds: Double { Double(position) / sampleRate }
}

/// One predicted beat the stream position has passed (ANL-005-R10).
public struct BeatEvent: Sendable, Hashable {
    /// 1, 2, 3… over the tracker's lifetime; never reused, not restarted by `reset()`.
    public let sequence: UInt64
    /// The predicted beat time, rounded to a sample.
    public let sampleIndex: Int64
    public let bpm: Double
    public let periodSamples: Double
    /// The estimate's confidence when the beat was reported.
    public let confidence: Double
    public let sampleRate: Double

    public init(sequence: UInt64, sampleIndex: Int64, bpm: Double, periodSamples: Double, confidence: Double,
                sampleRate: Double) {
        self.sequence = sequence
        self.sampleIndex = sampleIndex
        self.bpm = bpm
        self.periodSamples = periodSamples
        self.confidence = confidence
        self.sampleRate = sampleRate
    }

    /// `sampleIndex / sampleRate`.
    public var seconds: Double { Double(sampleIndex) / sampleRate }
}
