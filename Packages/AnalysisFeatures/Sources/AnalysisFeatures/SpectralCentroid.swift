// SpectralCentroid.swift — the spectral centroid, a brightness estimate in Hz and normalized 0…1
// (ANL-010-R1 to R5, R10, R11; research ANL-010-D1 to D8; contracts/spectral-centroid.md C2).
//
// Per frame: C = Σ f_k·m_k² / Σ m_k² over the `SpectralBinRange` of [lowerFrequency, Nyquist or
// upperFrequency] at the frame's own size and rate (power weighting: a noise floor or the window's
// sidelobes barely count, and with ANL-001's periodic Hann window a sine reads its own frequency).
// Normalized: n = clamp(log2(C / 50 Hz) / log2(10 kHz / 50 Hz), 0, 1), each octave the same step.
//
// Silence (ANL-010-R5): when the range's power relative to a full-scale sine (Σ m² / 1.5, the Hann
// power sum of a unit sine) is at or below the floor (−70 dB), the reading keeps its last values
// and reports no signal; before any frame above the floor both values are 0. Frames at another
// sample rate or with a wrong magnitude count leave the reading unchanged; non-finite magnitudes
// count as 0. No temporal smoothing: MOD-002 bindings carry their own envelope.
//
// Real-time safety (Constitution VII): a value type with no buffers; `process` allocates, locks,
// logs and reads no clock. Pure Swift (Linux, -DANALYSIS_NO_ACCELERATE). Nothing here reaches
// projectM (Constitution VIII, ADR-0008 decision 5).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum SpectralCentroidConfigurationError: Error, Equatable, Sendable {
    /// The sample rate must be finite and positive.
    case invalidSampleRate(Double)
    /// Lower must be finite, > 0 and below Nyquist; upper nil or finite and above lower.
    case invalidFrequencyRange(lower: Double, upper: Double?)
    /// The floor must be finite and below 0 dB.
    case invalidFloor(Float)
    /// The normalization range must be finite, positive and increasing.
    case invalidNormalizationRange(lower: Double, upper: Double)
}

public struct SpectralCentroidConfiguration: Sendable, Hashable {
    /// 44.1 kHz, 20 Hz to Nyquist, −70 dB floor, normalized 50 Hz–10 kHz (spec Clarifications).
    public static let standard = try! SpectralCentroidConfiguration()

    public let sampleRate: Double
    public let lowerFrequency: Double
    /// nil = Nyquist; a value above Nyquist is clipped to it.
    public let upperFrequency: Double?
    /// Silence floor, dB re a full-scale sine's power in range.
    public let floorDecibels: Float
    public let normalizationLower: Double
    public let normalizationUpper: Double
    /// Σ m² at the floor: 1.5 · 10^(floor/10).
    public let floorPower: Double

    public init(sampleRate: Double = 44_100, lowerFrequency: Double = 20, upperFrequency: Double? = nil,
                floorDecibels: Float = -70, normalizationLower: Double = 50,
                normalizationUpper: Double = 10_000) throws(SpectralCentroidConfigurationError) {
        guard sampleRate.isFinite, sampleRate > 0 else { throw .invalidSampleRate(sampleRate) }
        let nyquist: Double = sampleRate / 2
        guard lowerFrequency.isFinite, lowerFrequency > 0, lowerFrequency < nyquist else {
            throw .invalidFrequencyRange(lower: lowerFrequency, upper: upperFrequency)
        }
        if let upperFrequency {
            guard upperFrequency.isFinite, upperFrequency > lowerFrequency else {
                throw .invalidFrequencyRange(lower: lowerFrequency, upper: upperFrequency)
            }
        }
        guard floorDecibels.isFinite, floorDecibels < 0 else { throw .invalidFloor(floorDecibels) }
        guard normalizationLower.isFinite, normalizationUpper.isFinite, normalizationLower > 0,
              normalizationUpper > normalizationLower else {
            throw .invalidNormalizationRange(lower: normalizationLower, upper: normalizationUpper)
        }
        self.sampleRate = sampleRate
        self.lowerFrequency = lowerFrequency
        self.upperFrequency = upperFrequency
        self.floorDecibels = floorDecibels
        self.normalizationLower = normalizationLower
        self.normalizationUpper = normalizationUpper
        let exponent: Double = Double(floorDecibels) / 10
        let ratio: Double = pow(10, exponent)
        floorPower = 1.5 * ratio
    }

    /// clamp(log2(hz / lower) / log2(upper / lower), 0, 1); 0 for non-finite or non-positive input.
    public func normalized(hz: Double) -> Double {
        guard hz.isFinite, hz > 0 else { return 0 }
        let octaves: Double = log2(hz / normalizationLower)
        let span: Double = log2(normalizationUpper / normalizationLower)
        let position: Double = octaves / span
        return min(max(position, 0), 1)
    }

    /// The analysed bins at `size` (nil when the range holds none at this size).
    public func binRange(size: FFTSize) -> SpectralBinRange? {
        let nyquist: Double = sampleRate / 2
        let upper: Double = min(upperFrequency ?? nyquist, nyquist)
        return SpectralBinRange(lowerFrequency: lowerFrequency, upperFrequency: upper, size: size, sampleRate: sampleRate)
    }
}

/// One frame's brightness estimate.
public struct SpectralCentroidReading: Sendable, Hashable {
    /// No estimate yet: 0 Hz, 0 normalized, no signal.
    public static let none = SpectralCentroidReading(hz: 0, normalized: 0, hasSignal: false)

    /// Centroid in Hz (held at silence; 0 before any signal).
    public let hz: Float
    /// 0…1 log-frequency position of `hz` (held / 0 likewise).
    public let normalized: Float
    /// True when this frame was above the floor.
    public let hasSignal: Bool

    public init(hz: Float, normalized: Float, hasSignal: Bool) {
        self.hz = hz
        self.normalized = normalized
        self.hasSignal = hasSignal
    }
}

public struct SpectralCentroidEstimator: Sendable {
    public let configuration: SpectralCentroidConfiguration
    public private(set) var reading: SpectralCentroidReading = .none

    public init(configuration: SpectralCentroidConfiguration = .standard) {
        self.configuration = configuration
    }

    /// Back to `.none` (a session start).
    public mutating func reset() {
        reading = .none
    }

    /// Updates and returns the reading for one ANL-001 spectrum (`magnitudes` = `size.binCount`
    /// linear magnitudes). Allocation-, lock-, log- and clock-free.
    @discardableResult
    public mutating func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> SpectralCentroidReading {
        guard frame.sampleRate == configuration.sampleRate, magnitudes.count == frame.size.binCount else { return reading }
        let hold = SpectralCentroidReading(hz: reading.hz, normalized: reading.normalized, hasSignal: false)
        guard let range = configuration.binRange(size: frame.size) else {
            reading = hold
            return reading
        }
        let measured = Self.measure(magnitudes: magnitudes, size: frame.size, sampleRate: frame.sampleRate, range: range)
        guard measured.power > configuration.floorPower, measured.hz.isFinite, measured.hz > 0 else {
            reading = hold
            return reading
        }
        let normalized: Double = configuration.normalized(hz: measured.hz)
        reading = SpectralCentroidReading(hz: Float(measured.hz), normalized: Float(normalized), hasSignal: true)
        return reading
    }

    /// Σ f_k·m_k² / Σ m_k² (Hz) and Σ m_k² over `range`, accumulated in Double; non-finite
    /// magnitudes count as 0; (0, 0) when the power is 0 or `range` exceeds `magnitudes`.
    public static func measure(magnitudes: UnsafeBufferPointer<Float>, size: FFTSize, sampleRate: Double,
                               range: SpectralBinRange) -> (hz: Double, power: Double) {
        guard range.last < magnitudes.count else { return (0, 0) }
        var power: Double = 0
        var moment: Double = 0
        for k in range.first...range.last {
            let magnitude = Double(magnitudes[k])
            guard magnitude.isFinite else { continue }
            let binPower: Double = magnitude * magnitude
            power += binPower
            moment += Double(k) * binPower
        }
        guard power > 0, power.isFinite, moment.isFinite else { return (0, 0) }
        let meanBin: Double = moment / power
        let hz: Double = meanBin * size.binWidth(sampleRate: sampleRate)
        return (hz, power)
    }
}
