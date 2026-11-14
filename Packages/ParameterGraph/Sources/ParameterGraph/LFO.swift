// LFO.swift — clocked low-frequency oscillators, sine and triangle (MOD-007-R1 to R4, R6, R10;
// specs/156-mod-007-lfo, research MOD-007-D1 to D3, D5, contract L1 to L3).
//
// * The value is a pure function of the elapsed time since an origin, in integer nanoseconds:
//   φ = frac(phaseOffset + rate·t), value = clamp(center + amplitude/2 · w(φ), 0, 1), where w is
//   sin(2πφ) or the triangle with the same zero crossings and peaks (0, +1 at ¼, 0 at ½, −1 at ¾).
// * No accumulated state, so no drift. The phase splits t into whole seconds s and a remainder r; the
//   rounding error of rate·s is recovered exactly with a fused multiply-add, so the phase stays exact to
//   about 1e-16 cycles after hours or days (the acceptance tolerance is 1e-9).
// * The bank holds a scene's oscillators (at most 8) with one origin: the first sample after `set`.
//   `reduceFlashingMaximumRateHz` (3 Hz) is the effective-rate cap while Reduce flashing is on (FR-072,
//   ACC-012); the stored rate is unchanged.
// * Pure, allocation-free per sample; one owner (not `Sendable`), never from an audio callback
//   (Constitution VII). Foundation-free (the C math library only): builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The waveform of an oscillator; the raw value is the stored name.
public enum LFOShape: String, Sendable, Hashable, CaseIterable {
    case sine
    case triangle

    /// The bipolar waveform (−1…1) at phase `phi` in 0…<1.
    public func wave(_ phi: Double) -> Double {
        switch self {
        case .sine:
            return sin(2 * Double.pi * phi)
        case .triangle:
            if phi < 0.25 { return 4 * phi }
            if phi < 0.75 { return 2 - 4 * phi }
            return 4 * phi - 4
        }
    }
}

/// Why an oscillator or a bank was refused.
public enum LFOError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidSettings(reason: String)
    case tooManyOscillators(limit: Int)

    public var description: String {
        switch self {
        case let .invalidSettings(reason): "invalid oscillator: \(reason)"
        case let .tooManyOscillators(limit): "at most \(limit) oscillators are allowed"
        }
    }
}

/// One low-frequency oscillator (contract L1, L2).
public struct LFO: Sendable, Hashable {
    public var shape: LFOShape
    /// Cycles per second (0.01…20).
    public var rateHz: Double
    /// The phase at the origin, in cycles (0…1; 1 is the same as 0).
    public var phaseOffset: Double
    /// The peak-to-peak swing as a fraction of 0…1 (0…1).
    public var amplitude: Double
    /// The middle of the swing (0…1).
    public var center: Double

    public static let minimumRateHz = 0.01
    public static let maximumRateHz = 20.0
    public static let defaultPhaseOffset = 0.0
    public static let defaultAmplitude = 1.0
    public static let defaultCenter = 0.5

    /// A validated oscillator; throws `LFOError.invalidSettings` when `validationProblem` is not nil.
    public init(shape: LFOShape, rateHz: Double, phaseOffset: Double = LFO.defaultPhaseOffset,
                amplitude: Double = LFO.defaultAmplitude, center: Double = LFO.defaultCenter) throws(LFOError) {
        self.shape = shape
        self.rateHz = rateHz
        self.phaseOffset = phaseOffset
        self.amplitude = amplitude
        self.center = center
        if let problem = validationProblem { throw .invalidSettings(reason: problem) }
    }

    /// Nil exactly when the settings are valid (MOD-007-R1).
    public var validationProblem: String? {
        guard rateHz.isFinite, rateHz >= Self.minimumRateHz, rateHz <= Self.maximumRateHz else {
            return "the rate must be \(Self.minimumRateHz)…\(Self.maximumRateHz) Hz"
        }
        guard phaseOffset.isFinite, phaseOffset >= 0, phaseOffset <= 1 else { return "the phase must be 0…1 cycle" }
        guard amplitude.isFinite, amplitude >= 0, amplitude <= 1 else { return "the amplitude must be 0…1" }
        guard center.isFinite, center >= 0, center <= 1 else { return "the center must be 0…1" }
        return nil
    }

    /// frac(phaseOffset + rateHz·t) in 0…<1, with t = `elapsedNanoseconds` (research MOD-007-D2).
    public func phase(elapsedNanoseconds: UInt64, rateHz rate: Double) -> Double {
        let wholeSeconds = Double(elapsedNanoseconds / 1_000_000_000)   // exact below 2⁵³
        let remainder = Double(elapsedNanoseconds % 1_000_000_000) / 1e9
        let product: Double = rate * wholeSeconds
        let productError: Double = (-product).addingProduct(rate, wholeSeconds)   // exact rounding error of the product
        let productFraction: Double = product - product.rounded(.down)            // exact
        let cycles: Double = productFraction + productError + rate * remainder + phaseOffset
        let phi: Double = cycles - cycles.rounded(.down)
        return phi < 1 ? phi : 0
    }

    /// The output (0…1) after `elapsedNanoseconds`, running at min(rateHz, maximumRateHz).
    public func value(elapsedNanoseconds: UInt64, maximumRateHz: Double = .infinity) -> Double {
        let rate: Double = min(rateHz, maximumRateHz)
        let phi = phase(elapsedNanoseconds: elapsedNanoseconds, rateHz: rate)
        let raw: Double = center + amplitude / 2 * shape.wave(phi)
        guard raw.isFinite else { return min(max(center, 0), 1) }
        return min(max(raw, 0), 1)
    }
}

/// A scene's oscillators with one shared origin (contract L3).
public final class LFOBank {
    /// At most this many oscillators per bank (and per scene).
    public static let maximumOscillators = 8
    /// The effective-rate cap while Reduce flashing is on: 3 cycles per second (FR-072, WCAG 2.3.1).
    public static let reduceFlashingMaximumRateHz = 3.0

    /// The oscillators by position; nil keeps the position of an unusable scene entry (it reads 0).
    public private(set) var oscillators: [LFO?] = []
    private var origin: UInt64?

    public init() {}

    public var hasOscillators: Bool { oscillators.contains { (o: LFO?) -> Bool in o != nil } }

    /// Validates and replaces every oscillator; the origin restarts at the next sample. Unchanged on error.
    public func set(_ oscillators: [LFO?]) throws(LFOError) {
        guard oscillators.count <= Self.maximumOscillators else { throw .tooManyOscillators(limit: Self.maximumOscillators) }
        for case let lfo? in oscillators {
            if let problem = lfo.validationProblem { throw .invalidSettings(reason: problem) }
        }
        self.oscillators = oscillators
        origin = nil
    }

    /// Writes each slot's value at `timeNanoseconds` into `output` (0 for an empty or missing slot). The first call
    /// after `set` defines the origin; a time at or before the origin reads elapsed 0. Allocation-free.
    public func values(atNanoseconds timeNanoseconds: UInt64, maximumRateHz: Double = .infinity,
                       into output: UnsafeMutableBufferPointer<Double>) {
        let start: UInt64 = origin ?? timeNanoseconds
        origin = start
        let elapsed: UInt64 = timeNanoseconds > start ? timeNanoseconds - start : 0
        for i in output.indices {
            if i < oscillators.count, let lfo = oscillators[i] {
                output[i] = lfo.value(elapsedNanoseconds: elapsed, maximumRateHz: maximumRateHz)
            } else {
                output[i] = 0
            }
        }
    }
}
