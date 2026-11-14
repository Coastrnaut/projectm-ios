// SpectralRolloff.swift — the spectral rolloff: the frequency below which a fraction p of the
// spectrum's power lies, in Hz and normalized 0…1 (ANL-011-R1 to R6, R10, R11; research ANL-011-D1
// to D8; contracts/spectral-rolloff.md C1, C2).
//
// Per frame, over ANL-010's `SpectralBinRange` (whole bins from 20 Hz, DC excluded, through Nyquist):
// P_k = m_k² (power), T = Σ P_k. Each bin's power is spread evenly over its own width
// [(k − ½)·Δf, (k + ½)·Δf], so the cumulative power is piecewise linear and the rolloff is where it
// reaches p·T: with k the first bin whose inclusive sum S_k ≥ p·T,
//     rolloff = (k − ½ + (p·T − S_{k−1}) / P_k) · Δf, clamped to [0, Nyquist].
// A lone tone at bin k reads (k − ½ + p)·Δf; flat power over bins 1…K reads (½ + p·K)·Δf.
// Normalized: n = clamp(log2(f / 50 Hz) / log2(20 kHz / 50 Hz), 0, 1), like ANL-010's centroid.
//
// Silence (ANL-011-R5): when the range's power relative to a full-scale sine (Σ m² / 1.5) is at or
// below the floor (−70 dB), the reading is 0 Hz, 0 normalized, no signal (unlike the centroid, which
// holds: MOD-002 bindings ease the drop with their release). Frames at another sample rate or with a
// wrong magnitude count leave the reading unchanged; non-finite magnitudes count as 0.
//
// Backends (ANL-011-R6): the total uses `vDSP_svesq` when Accelerate is compiled in and the backend
// allows it (a non-finite total falls back to the portable loop); the cumulative scan is portable.
// No extra FFT: the frame's own magnitudes are read. Real-time safety (Constitution VII): a value
// type with no buffers; `process` allocates, locks, logs and reads no clock. Nothing here reaches
// projectM (Constitution VIII).
#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
import Accelerate
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum SpectralRolloffConfigurationError: Error, Equatable, Sendable {
    /// The sample rate must be finite and positive.
    case invalidSampleRate(Double)
    /// Lower must be finite, > 0 and below Nyquist; upper nil or finite and above lower.
    case invalidFrequencyRange(lower: Double, upper: Double?)
    /// The fraction must be finite and within 0.5…0.99.
    case invalidFraction(Double)
    /// The floor must be finite and below 0 dB.
    case invalidFloor(Float)
    /// The normalization range must be finite, positive and increasing.
    case invalidNormalizationRange(lower: Double, upper: Double)
}

public struct SpectralRolloffConfiguration: Sendable, Hashable {
    /// 44.1 kHz, 20 Hz to Nyquist, p = 0.85, −70 dB floor, normalized 50 Hz–20 kHz (spec Clarifications).
    public static let standard = try! SpectralRolloffConfiguration()
    /// The accepted fractions (ANL-011-R3).
    public static let fractionRange: ClosedRange<Double> = 0.5...0.99

    public let sampleRate: Double
    public let lowerFrequency: Double
    /// nil = Nyquist; a value above Nyquist is clipped to it.
    public let upperFrequency: Double?
    /// The power fraction p below the rolloff.
    public let fraction: Double
    /// Silence floor, dB re a full-scale sine's power in range.
    public let floorDecibels: Float
    public let normalizationLower: Double
    public let normalizationUpper: Double
    /// Σ m² at the floor: 1.5 · 10^(floor/10).
    public let floorPower: Double

    public init(sampleRate: Double = 44_100, lowerFrequency: Double = 20, upperFrequency: Double? = nil,
                fraction: Double = 0.85, floorDecibels: Float = -70, normalizationLower: Double = 50,
                normalizationUpper: Double = 20_000) throws(SpectralRolloffConfigurationError) {
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
        guard fraction.isFinite, Self.fractionRange.contains(fraction) else { throw .invalidFraction(fraction) }
        guard floorDecibels.isFinite, floorDecibels < 0 else { throw .invalidFloor(floorDecibels) }
        guard normalizationLower.isFinite, normalizationUpper.isFinite, normalizationLower > 0,
              normalizationUpper > normalizationLower else {
            throw .invalidNormalizationRange(lower: normalizationLower, upper: normalizationUpper)
        }
        self.sampleRate = sampleRate
        self.lowerFrequency = lowerFrequency
        self.upperFrequency = upperFrequency
        self.fraction = fraction
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

/// One frame's rolloff.
public struct SpectralRolloffReading: Sendable, Hashable {
    /// No signal: 0 Hz, 0 normalized.
    public static let none = SpectralRolloffReading(hz: 0, normalized: 0, hasSignal: false)

    /// Rolloff in Hz (0 at silence).
    public let hz: Float
    /// 0…1 log-frequency position of `hz` (0 at silence).
    public let normalized: Float
    /// True when this frame was above the floor.
    public let hasSignal: Bool

    public init(hz: Float, normalized: Float, hasSignal: Bool) {
        self.hz = hz
        self.normalized = normalized
        self.hasSignal = hasSignal
    }
}

public struct SpectralRolloffEstimator: Sendable {
    public let configuration: SpectralRolloffConfiguration
    /// `.accelerated` when vDSP computes the total, else `.portable`.
    public let resolvedBackend: SpectrumBackend
    public private(set) var reading: SpectralRolloffReading = .none

    public init(configuration: SpectralRolloffConfiguration = .standard, backend: SpectrumBackend = .automatic) {
        self.configuration = configuration
        resolvedBackend = Self.resolve(backend)
    }

    /// Back to `.none` (a session start).
    public mutating func reset() {
        reading = .none
    }

    /// Updates and returns the reading for one ANL-001 spectrum (`magnitudes` = `size.binCount`
    /// linear magnitudes). Allocation-, lock-, log- and clock-free.
    @discardableResult
    public mutating func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> SpectralRolloffReading {
        guard frame.sampleRate == configuration.sampleRate, magnitudes.count == frame.size.binCount else { return reading }
        guard let range = configuration.binRange(size: frame.size) else {
            reading = .none
            return reading
        }
        let measured = Self.measure(magnitudes: magnitudes, range: range, fraction: configuration.fraction,
                                    binWidth: frame.size.binWidth(sampleRate: frame.sampleRate),
                                    nyquist: frame.sampleRate / 2, backend: resolvedBackend)
        guard measured.power > configuration.floorPower, measured.hz.isFinite, measured.hz > 0 else {
            reading = .none
            return reading
        }
        let normalized: Double = configuration.normalized(hz: measured.hz)
        reading = SpectralRolloffReading(hz: Float(measured.hz), normalized: Float(normalized), hasSignal: true)
        return reading
    }

    /// The rolloff (Hz) at `fraction` of Σ m_k² over `range` and that power; non-finite magnitudes
    /// count as 0; (0, 0) when the power is 0 or not finite or `range` exceeds `magnitudes`.
    public static func measure(magnitudes: UnsafeBufferPointer<Float>, range: SpectralBinRange, fraction: Double,
                               binWidth: Double, nyquist: Double, backend: SpectrumBackend = .automatic) -> (hz: Double, power: Double) {
        guard range.last < magnitudes.count, let base = magnitudes.baseAddress else { return (0, 0) }
        let total: Double = totalPower(base, range: range, backend: resolve(backend))
        guard total > 0, total.isFinite else { return (0, 0) }
        let target: Double = fraction * total
        var below: Double = 0   // S_{k−1}
        for k in range.first...range.last {
            let magnitude = Double(base[k])
            guard magnitude.isFinite else { continue }
            let binPower: Double = magnitude * magnitude
            let through: Double = below + binPower   // S_k
            if through >= target, binPower > 0 {
                let inside: Double = (target - below) / binPower
                let position: Double = Double(k) - 0.5 + min(max(inside, 0), 1)
                return (min(max(position * binWidth, 0), nyquist), total)
            }
            below = through
        }
        // Rounding between the vDSP total and the scan: the crossing is at the top of the range.
        let top: Double = (Double(range.last) + 0.5) * binWidth
        return (min(max(top, 0), nyquist), total)
    }

    // MARK: Backend

    private static func resolve(_ backend: SpectrumBackend) -> SpectrumBackend {
        switch backend {
        case .portable: .portable
        case .automatic, .accelerated: SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable
        }
    }

    /// Σ m_k² over `range`: vDSP when `backend` is `.accelerated` and its sum is finite, else portable.
    private static func totalPower(_ base: UnsafePointer<Float>, range: SpectralBinRange, backend: SpectrumBackend) -> Double {
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        if backend == .accelerated {
            var sum: Float = 0
            vDSP_svesq(base + range.first, 1, &sum, vDSP_Length(range.count))
            if sum.isFinite { return Double(sum) }
        }
        #endif
        return portableTotal(base, range: range)
    }

    private static func portableTotal(_ base: UnsafePointer<Float>, range: SpectralBinRange) -> Double {
        var power: Double = 0
        for k in range.first...range.last {
            let magnitude = Double(base[k])
            guard magnitude.isFinite else { continue }
            power += magnitude * magnitude
        }
        return power
    }
}
