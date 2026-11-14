// TransientDetectorConfiguration.swift — parameters of the band-limited transient detector and the
// event it reports (ANL-007-R1 to R9; data-model.md; contracts/transient-detector.md C1; defaults
// and their reasons in spec Clarifications and research ANL-007-D1 to D4).
//
// One detector type serves every band: the kick (ANL-007) is `.kick`, the mid transient (ANL-008,
// 1–4 kHz) is `.midTransient`; ANL-009 (high-frequency) adds a `TransientBand` case and its own
// configuration. Invalid configurations cannot be constructed. Every event carries a confidence
// (ANL-008-R6): √(margin · breadth′), see `breadthWeight` and `confidenceMarginDecibels`.
//
// The mid transient is NOT a snare classifier (ANL-008-R1): it reports percussive energy rising in
// 1–4 kHz, whatever made it, and no name, event or value claims an instrument.
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
}

public struct TransientDetectorConfiguration: Sendable, Hashable {
    /// Capacity of the detection-value window; the median/MAD window never spans more frames.
    public static let maximumBaselineFrames = 128
    /// Capacity of the level history the flux reference is taken from.
    public static let maximumReferenceFrames = 8

    /// The kick at 44,100 Hz (the normalized stream's rate), without a throwing call.
    public static let kick = TransientDetectorConfiguration(
        validBand: .kick, sampleRate: 44_100, lowerFrequency: 40, upperFrequency: 150, floorDecibels: -70,
        dominanceDecibels: -15, baselineSeconds: 1.0, minimumRiseDecibels: 9, deviationMultiplier: 4,
        refractorySeconds: 0.1, envelopeSeconds: 0.1, breadthWeight: 0, confidenceMarginDecibels: 12)

    /// The mid transient at 44,100 Hz (ANL-008; spec Clarifications): 1–4 kHz, 70 ms refractory,
    /// 80 ms envelope, confidence weighted by the attack's breadth.
    public static let midTransient = TransientDetectorConfiguration(
        validBand: .midTransient, sampleRate: 44_100, lowerFrequency: 1_000, upperFrequency: 4_000, floorDecibels: -70,
        dominanceDecibels: -15, baselineSeconds: 1.0, minimumRiseDecibels: 9, deviationMultiplier: 4,
        refractorySeconds: 0.07, envelopeSeconds: 0.08, breadthWeight: 1, confidenceMarginDecibels: 12)

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

    public init(band: TransientBand = .kick, sampleRate: Double = 44_100,
                lowerFrequency: Double = 40, upperFrequency: Double = 150,
                floorDecibels: Float = -70, dominanceDecibels: Float = -15,
                baselineSeconds: Double = 1.0, minimumRiseDecibels: Float = 9,
                deviationMultiplier: Float = 4, refractorySeconds: Double = 0.1,
                envelopeSeconds: Double = 0.1, breadthWeight: Float = 0,
                confidenceMarginDecibels: Float = 12) throws(TransientDetectorConfigurationError) {
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
        self.init(validBand: band, sampleRate: sampleRate, lowerFrequency: lowerFrequency, upperFrequency: upperFrequency,
                  floorDecibels: floorDecibels, dominanceDecibels: dominanceDecibels, baselineSeconds: baselineSeconds,
                  minimumRiseDecibels: minimumRiseDecibels, deviationMultiplier: deviationMultiplier,
                  refractorySeconds: refractorySeconds, envelopeSeconds: envelopeSeconds, breadthWeight: breadthWeight,
                  confidenceMarginDecibels: confidenceMarginDecibels)
    }

    private init(validBand: TransientBand, sampleRate: Double, lowerFrequency: Double, upperFrequency: Double,
                 floorDecibels: Float, dominanceDecibels: Float, baselineSeconds: Double, minimumRiseDecibels: Float,
                 deviationMultiplier: Float, refractorySeconds: Double, envelopeSeconds: Double, breadthWeight: Float,
                 confidenceMarginDecibels: Float) {
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
