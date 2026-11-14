// SpectralFlatness.swift — spectral flatness (Wiener entropy): how noise-like a spectrum is, 0…1
// (ANL-012-R1 to R5, R9, R10; research ANL-012-D1 to D6; contracts/spectral-flatness.md C1, C2).
//
// Per frame, over ANL-010's `SpectralBinRange` (whole bins from 20 Hz, DC excluded, through Nyquist),
// with K bins and P_k = m_k² (power):
//     A = (1/K)·Σ P_k,   ε = 10⁻¹²·A,   G = exp((1/K)·Σ ln(P_k + ε)),   F = clamp(G / A, 0, 1).
// ε is relative to the frame's mean power (−120 dB below it), so F is scale-invariant and a zero bin
// is finite in the log. A lone tone reads ≈ 10⁻⁹ (tonal), white noise ≈ e^−γ ≈ 0.56 (its bin powers
// are exponentially distributed), equal power in every bin reads 1.
//
// Silence (ANL-012-R4, ANL-011's rule): when the range's power relative to a full-scale sine
// (Σ m² / 1.5) is at or below the floor (−70 dB), the reading is 0 with no signal, so silence and
// dither never read as noise. Frames at another sample rate or with a wrong magnitude count leave
// the reading unchanged; non-finite magnitudes count as power 0 (they stay in K).
//
// Backends (ANL-012-R5): the total uses `vDSP_svesq` when Accelerate is compiled in and the backend
// allows it (a non-finite total falls back to the portable loop); it gates silence (a silent frame
// skips the log pass) and sets ε. The log pass is a portable Double loop on both backends (a vector
// log would need a scratch buffer) and also sums the power in Double for the ratio's mean, so a flat
// spectrum reads 1 within 10⁻¹² on either backend. No extra FFT. Real-time safety
// (Constitution VII): a value type with no buffers; `process` allocates, locks, logs and reads no
// clock. Nothing here reaches projectM (Constitution VIII). ANL-008's private band breadth (Float,
// band-limited, absolute floor) is a different measure and is left unchanged.
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

public enum SpectralFlatnessConfigurationError: Error, Equatable, Sendable {
    /// The sample rate must be finite and positive.
    case invalidSampleRate(Double)
    /// Lower must be finite, > 0 and below Nyquist; upper nil or finite and above lower.
    case invalidFrequencyRange(lower: Double, upper: Double?)
    /// The floor must be finite and below 0 dB.
    case invalidFloor(Float)
}

public struct SpectralFlatnessConfiguration: Sendable, Hashable {
    /// 44.1 kHz, 20 Hz to Nyquist, −70 dB floor (spec Clarifications).
    public static let standard = try! SpectralFlatnessConfiguration()
    /// ε = relativeEpsilon × the frame's mean bin power (research ANL-012-D2).
    public static let relativeEpsilon: Double = 1e-12

    public let sampleRate: Double
    public let lowerFrequency: Double
    /// nil = Nyquist; a value above Nyquist is clipped to it.
    public let upperFrequency: Double?
    /// Silence floor, dB re a full-scale sine's power in range.
    public let floorDecibels: Float
    /// Σ m² at the floor: 1.5 · 10^(floor/10).
    public let floorPower: Double

    public init(sampleRate: Double = 44_100, lowerFrequency: Double = 20, upperFrequency: Double? = nil,
                floorDecibels: Float = -70) throws(SpectralFlatnessConfigurationError) {
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
        self.sampleRate = sampleRate
        self.lowerFrequency = lowerFrequency
        self.upperFrequency = upperFrequency
        self.floorDecibels = floorDecibels
        let exponent: Double = Double(floorDecibels) / 10
        let ratio: Double = pow(10, exponent)
        floorPower = 1.5 * ratio
    }

    /// The analysed bins at `size` (nil when the range holds none at this size).
    public func binRange(size: FFTSize) -> SpectralBinRange? {
        let nyquist: Double = sampleRate / 2
        let upper: Double = min(upperFrequency ?? nyquist, nyquist)
        return SpectralBinRange(lowerFrequency: lowerFrequency, upperFrequency: upper, size: size, sampleRate: sampleRate)
    }
}

/// One frame's flatness.
public struct SpectralFlatnessReading: Sendable, Hashable {
    /// No signal: 0.
    public static let none = SpectralFlatnessReading(flatness: 0, hasSignal: false)

    /// 0 (tonal) … 1 (flat); 0 at silence.
    public let flatness: Float
    /// True when this frame was above the floor.
    public let hasSignal: Bool

    public init(flatness: Float, hasSignal: Bool) {
        self.flatness = flatness
        self.hasSignal = hasSignal
    }
}

public struct SpectralFlatnessEstimator: Sendable {
    public let configuration: SpectralFlatnessConfiguration
    /// `.accelerated` when vDSP computes the total, else `.portable`.
    public let resolvedBackend: SpectrumBackend
    public private(set) var reading: SpectralFlatnessReading = .none

    public init(configuration: SpectralFlatnessConfiguration = .standard, backend: SpectrumBackend = .automatic) {
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
    public mutating func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> SpectralFlatnessReading {
        guard frame.sampleRate == configuration.sampleRate, magnitudes.count == frame.size.binCount else { return reading }
        guard let range = configuration.binRange(size: frame.size) else {
            reading = .none
            return reading
        }
        let measured = Self.measure(magnitudes: magnitudes, range: range, backend: resolvedBackend)
        guard measured.power > configuration.floorPower, measured.flatness.isFinite else {
            reading = .none
            return reading
        }
        reading = SpectralFlatnessReading(flatness: Float(measured.flatness), hasSignal: true)
        return reading
    }

    /// The flatness over `range` and its power Σ m_k²; non-finite magnitudes count as 0; (0, 0)
    /// when the power is 0 or not finite or `range` exceeds `magnitudes`.
    public static func measure(magnitudes: UnsafeBufferPointer<Float>, range: SpectralBinRange,
                               backend: SpectrumBackend = .automatic) -> (flatness: Double, power: Double) {
        guard range.last < magnitudes.count, let base = magnitudes.baseAddress else { return (0, 0) }
        let total: Double = totalPower(base, range: range, backend: resolve(backend))
        guard total > 0, total.isFinite else { return (0, 0) }
        let count = Double(range.count)
        let mean: Double = total / count
        let epsilon: Double = SpectralFlatnessConfiguration.relativeEpsilon * mean
        var logSum: Double = 0
        var exactSum: Double = 0   // the ratio's mean, in Double on both backends
        for k in range.first...range.last {
            let magnitude = Double(base[k])
            let binPower: Double = magnitude.isFinite ? magnitude * magnitude : 0
            logSum += log(binPower + epsilon)
            exactSum += binPower
        }
        let geometric: Double = exp(logSum / count)
        let ratio: Double = geometric / (exactSum / count)
        guard ratio.isFinite else { return (0, total) }
        return (min(max(ratio, 0), 1), total)
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
