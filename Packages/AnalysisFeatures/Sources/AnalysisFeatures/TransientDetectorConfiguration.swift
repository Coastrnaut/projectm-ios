// TransientDetectorConfiguration.swift — parameters of the band-limited transient detector and the
// event it reports (ANL-007-R1 to R9; data-model.md; contracts/transient-detector.md C1; defaults
// and their reasons in spec Clarifications and research ANL-007-D1 to D4).
//
// One detector type serves every band: the kick (ANL-007) is `.kick`, the mid transient (ANL-008,
// 1–4 kHz) is `.midTransient`, the high transient (ANL-009, 6–16 kHz) is `.highTransient`.
// Invalid configurations cannot be constructed. Every event carries a confidence (ANL-008-R6):
// √(margin · breadth′), see `breadthWeight` and `confidenceMarginDecibels`. A configuration may cap
// its event rate (ANL-009-R4): at most `maximumEventsPerSecond` events in any 1 s span.
//
// The mid transient is NOT a snare classifier (ANL-008-R1) and the high transient is NOT a hi-hat
// classifier (ANL-009-R1): each reports percussive energy rising in its band, whatever made it,
// and no name, event or value claims an instrument.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Which band detector produced an event.
public enum TransientBand: Sendable, Hashable, CaseIterable {
    /// Low-frequency transients, 40–150 Hz (ANL-007).
    case kick
    /// Mid-band percussive transients, 1–4 kHz (ANL-008); no instrument identity is implied.
    case midTransient
    /// High-band percussive transients, 6–16 kHz (ANL-009); no instrument identity is implied.
    case highTransient
}

public enum TransientDetectorConfigurationError: Error, Equatable, Sendable {
    /// Finite and at least `BandLayout.minimumSampleRate` (8,000 Hz).
    case invalidSampleRate(Double)
    /// 20 Hz ≤ lower < upper ≤ rate / 2.
    case invalidFrequencyRange(lower: Double, upper: Double)
    /// −120…−20 dB.
    case invalidFloor(Float)
    /// −60…0 dB.
    case invalidDominance(Float)
    /// Greater than 0 and at most 2 s.
    case invalidBaselineWindow(Double)
    /// Greater than 0 and at most 40 dB.
    case invalidMinimumRise(Float)
    /// 0…20.
    case invalidDeviationMultiplier(Float)
    /// 0…2 s.
    case invalidRefractoryPeriod(Double)
    /// Greater than 0 and at most 5 s.
    case invalidEnvelopeTime(Double)
    /// 0…1.
    case invalidBreadthWeight(Float)
    /// Greater than 0 and at most 40 dB.
    case invalidConfidenceMargin(Float)
    /// 0 (no cap) … `maximumEventRateCapacity`.
    case invalidMaximumEventRate(Int)
}

public struct TransientDetectorConfiguration: Sendable, Hashable {
    /// Capacity of the detection-value window; the median/MAD window never spans more frames.
    public static let maximumBaselineFrames = 128
    /// Capacity of the level history the flux reference is taken from.
    public static let maximumReferenceFrames = 8
    /// The highest per-second event cap (the detector keeps this many event times).
    public static let maximumEventRateCapacity = 64

    /// The kick at 44,100 Hz (the normalized stream's rate), without a throwing call.
    public static let kick = TransientDetectorConfiguration(
        validBand: .kick, sampleRate: 44_100, lowerFrequency: 40, upperFrequency: 150, floorDecibels: -70,
        dominanceDecibels: -15, baselineSeconds: 1.0, minimumRiseDecibels: 9, deviationMultiplier: 4,
        refractorySeconds: 0.1, envelopeSeconds: 0.1, breadthWeight: 0, confidenceMarginDecibels: 12,
        maximumEventsPerSecond: 0)

    /// The mid transient at 44,100 Hz (ANL-008; spec Clarifications): 1–4 kHz, 70 ms refractory,
    /// 80 ms envelope, confidence weighted by the attack's breadth.
    public static let midTransient = TransientDetectorConfiguration(
        validBand: .midTransient, sampleRate: 44_100, lowerFrequency: 1_000, upperFrequency: 4_000, floorDecibels: -70,
        dominanceDecibels: -15, baselineSeconds: 1.0, minimumRiseDecibels: 9, deviationMultiplier: 4,
        refractorySeconds: 0.07, envelopeSeconds: 0.08, breadthWeight: 1, confidenceMarginDecibels: 12,
        maximumEventsPerSecond: 0)

    /// The high transient at 44,100 Hz (ANL-009; spec Clarifications): 6–16 kHz, −6 dB dominance
    /// (the band must hold a quarter of the power increase, so a mid-band hit's upper tail does not
    /// fire), 40 ms refractory, 50 ms envelope, confidence weighted by the attack's breadth, at most
    /// 12 events in any 1 s.
    public static let highTransient = TransientDetectorConfiguration(
        validBand: .highTransient, sampleRate: 44_100, lowerFrequency: 6_000, upperFrequency: 16_000, floorDecibels: -70,
        dominanceDecibels: -6, baselineSeconds: 1.0, minimumRiseDecibels: 9, deviationMultiplier: 4,
        refractorySeconds: 0.04, envelopeSeconds: 0.05, breadthWeight: 1, confidenceMarginDecibels: 12,
        maximumEventsPerSecond: 12)

    public let band: TransientBand
    /// Hz; one detector serves one sample rate (its weight tables are built for it).
    public let sampleRate: Double
    /// The band's edges in Hz; bins are weighted by ANL-002's overlap rule.
    public let lowerFrequency: Double
    public let upperFrequency: Double
    /// Band levels are clamped here (dB re a full-scale sine in band); no event at or below it.
    public let floorDecibels: Float
    /// Minimum share of the frame's power increase (over the flux reference frame) the band must
    /// hold for an event, in dB.
    public let dominanceDecibels: Float
    /// Length of the window of detection values whose median and MAD set the threshold.
    public let baselineSeconds: Double
    /// The threshold never falls below this rise, in dB.
    public let minimumRiseDecibels: Float
    /// k in median + k · MAD.
    public let deviationMultiplier: Float
    /// Events closer than this to the previous event are suppressed.
    public let refractorySeconds: Double
    /// Time constant of the envelope's exponential decay.
    public let envelopeSeconds: Double
    /// w in the confidence's breadth′ = 1 − w + w · breadth (0: the confidence is the margin alone).
    public let breadthWeight: Float
    /// The rise above the threshold that gives a full margin (margin = excess / this, clamped 0…1).
    public let confidenceMarginDecibels: Float
    /// At most this many events in any span of `rateWindowSamples` (1 s); 0 = no cap (ANL-009-R4).
    /// An event the cap suppresses counts as not fired: the detector disarms as usual.
    public let maximumEventsPerSecond: Int

    public init(band: TransientBand = .kick, sampleRate: Double = 44_100,
                lowerFrequency: Double = 40, upperFrequency: Double = 150,
                floorDecibels: Float = -70, dominanceDecibels: Float = -15,
                baselineSeconds: Double = 1.0, minimumRiseDecibels: Float = 9,
                deviationMultiplier: Float = 4, refractorySeconds: Double = 0.1,
                envelopeSeconds: Double = 0.1, breadthWeight: Float = 0,
                confidenceMarginDecibels: Float = 12,
                maximumEventsPerSecond: Int = 0) throws(TransientDetectorConfigurationError) {
        guard sampleRate.isFinite, sampleRate >= BandLayout.minimumSampleRate else { throw .invalidSampleRate(sampleRate) }
        let nyquist: Double = sampleRate / 2
        guard lowerFrequency.isFinite, upperFrequency.isFinite, lowerFrequency >= BandLayout.lowerEdgeHz,
              lowerFrequency < upperFrequency, upperFrequency <= nyquist else {
            throw .invalidFrequencyRange(lower: lowerFrequency, upper: upperFrequency)
        }
        guard floorDecibels >= -120, floorDecibels <= -20 else { throw .invalidFloor(floorDecibels) }
        guard dominanceDecibels >= -60, dominanceDecibels <= 0 else { throw .invalidDominance(dominanceDecibels) }
        guard baselineSeconds > 0, baselineSeconds <= 2 else { throw .invalidBaselineWindow(baselineSeconds) }
        guard minimumRiseDecibels > 0, minimumRiseDecibels <= 40 else { throw .invalidMinimumRise(minimumRiseDecibels) }
        guard deviationMultiplier >= 0, deviationMultiplier <= 20 else { throw .invalidDeviationMultiplier(deviationMultiplier) }
        guard refractorySeconds >= 0, refractorySeconds <= 2 else { throw .invalidRefractoryPeriod(refractorySeconds) }
        guard envelopeSeconds > 0, envelopeSeconds <= 5 else { throw .invalidEnvelopeTime(envelopeSeconds) }
        guard breadthWeight >= 0, breadthWeight <= 1 else { throw .invalidBreadthWeight(breadthWeight) }
        guard confidenceMarginDecibels > 0, confidenceMarginDecibels <= 40 else {
            throw .invalidConfidenceMargin(confidenceMarginDecibels)
        }
        guard maximumEventsPerSecond >= 0, maximumEventsPerSecond <= TransientDetectorConfiguration.maximumEventRateCapacity else {
            throw .invalidMaximumEventRate(maximumEventsPerSecond)
        }
        self.init(validBand: band, sampleRate: sampleRate, lowerFrequency: lowerFrequency, upperFrequency: upperFrequency,
                  floorDecibels: floorDecibels, dominanceDecibels: dominanceDecibels, baselineSeconds: baselineSeconds,
                  minimumRiseDecibels: minimumRiseDecibels, deviationMultiplier: deviationMultiplier,
                  refractorySeconds: refractorySeconds, envelopeSeconds: envelopeSeconds, breadthWeight: breadthWeight,
                  confidenceMarginDecibels: confidenceMarginDecibels, maximumEventsPerSecond: maximumEventsPerSecond)
    }

    private init(validBand: TransientBand, sampleRate: Double, lowerFrequency: Double, upperFrequency: Double,
                 floorDecibels: Float, dominanceDecibels: Float, baselineSeconds: Double, minimumRiseDecibels: Float,
                 deviationMultiplier: Float, refractorySeconds: Double, envelopeSeconds: Double, breadthWeight: Float,
                 confidenceMarginDecibels: Float, maximumEventsPerSecond: Int) {
        band = validBand
        self.sampleRate = sampleRate
        self.lowerFrequency = lowerFrequency
        self.upperFrequency = upperFrequency
        self.floorDecibels = floorDecibels
        self.dominanceDecibels = dominanceDecibels
        self.baselineSeconds = baselineSeconds
        self.minimumRiseDecibels = minimumRiseDecibels
        self.deviationMultiplier = deviationMultiplier
        self.refractorySeconds = refractorySeconds
        self.envelopeSeconds = envelopeSeconds
        self.breadthWeight = breadthWeight
        self.confidenceMarginDecibels = confidenceMarginDecibels
        self.maximumEventsPerSecond = maximumEventsPerSecond
    }

    /// Detection values in the median/MAD window at `hop`: round(window · rate / hop), 1…128.
    public func baselineFrames(hop: Int) -> Int {
        guard hop > 0 else { return 1 }
        let frames: Double = (baselineSeconds * sampleRate / Double(hop)).rounded()
        let clamped: Double = min(max(frames, 1), Double(TransientDetectorConfiguration.maximumBaselineFrames))
        return Int(clamped)
    }

    /// round(refractory · rate).
    public var refractorySamples: Int64 {
        let samples: Double = (refractorySeconds * sampleRate).rounded()
        return Int64(samples)
    }

    /// The event cap's window: round(1 s · rate) samples (ANL-009-R4).
    public var rateWindowSamples: Int64 {
        let samples: Double = sampleRate.rounded()
        return Int64(samples)
    }

    /// The envelope's per-frame factor at `hop`: exp(−hop / (τ · rate)).
    public func envelopeDecay(hop: Int) -> Float {
        let exponent: Double = -Double(max(hop, 0)) / (envelopeSeconds * sampleRate)
        return Float(exp(exponent))
    }
}

/// One detected transient (ANL-007-R7). Times are on the stream's sample clock.
public struct TransientEvent: Sendable, Hashable {
    public let band: TransientBand
    /// 1, 2, 3… over the detector's lifetime; never reused, not restarted by `reset()`.
    public let sequence: UInt64
    /// First sample of the producing frame's newest hop: `frame.index + size − hop` (ANL-004-R6).
    public let sampleIndex: Int64
    /// The producing frame's first sample.
    public let frameIndex: Int64
    /// The detection value: the band level's rise over its recent minimum, dB.
    public let strength: Float
    /// The threshold the strength crossed, dB.
    public let threshold: Float
    /// The band level, dB re a full-scale sine in band.
    public let level: Float
    public let sampleRate: Double
    /// The producing frame's timestamp.
    public let timestampNanoseconds: UInt64
    /// 0…1 (ANL-008-R6): √(margin · breadth′), how far above the threshold and how broadband the
    /// attack was. An estimate of how clearly this is a percussive transient in the band, never of
    /// which instrument made it.
    public let confidence: Float

    public init(band: TransientBand, sequence: UInt64, sampleIndex: Int64, frameIndex: Int64, strength: Float,
                threshold: Float, level: Float, sampleRate: Double, timestampNanoseconds: UInt64, confidence: Float = 1) {
        self.band = band
        self.sequence = sequence
        self.sampleIndex = sampleIndex
        self.frameIndex = frameIndex
        self.strength = strength
        self.threshold = threshold
        self.level = level
        self.sampleRate = sampleRate
        self.timestampNanoseconds = timestampNanoseconds
        self.confidence = confidence
    }

    /// `sampleIndex / sampleRate`.
    public var seconds: Double { Double(sampleIndex) / sampleRate }
}
