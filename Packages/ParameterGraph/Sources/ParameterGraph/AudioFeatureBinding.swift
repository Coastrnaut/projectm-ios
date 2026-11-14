// AudioFeatureBinding.swift — one audio feature bound to one parameter, and why a binding is
// refused (MOD-002-R2 to R4; research MOD-002-D4, D5; contract C2).
//
// A binding maps the feature's position in the input range (0…1, clamped) to the output range
// with its `LinearMapping` (MOD-003),
// shaped by its `MappingCurve` (MOD-004; linear by default),
// optionally smoothed by an attack/release envelope (one-pole time constants, MOD-005), and
// combines it with the parameter's manual value by the mix mode. `AudioFeatureModulator.bind`
// validates it against the registry.
import Foundation

/// Rise and fall time constants of a one-pole envelope, in seconds; 0 means no smoothing
/// (MOD-002; definition and step MOD-005-R1 to R6, R11, contract E1, E2).
///
/// Definition: after the target steps from s₀ to x, the signal is `x + (s₀ − x)·exp(−t/τ)`, so it
/// covers 63.2 % of the distance at t = τ (86.5 % at 2τ, 95 % at 3τ). The 10–90 % rise time is
/// `τ·ln 9 ≈ 2.197 τ` (`riseTime10To90(timeConstant:)`). `attackSeconds` is τ while the target is
/// above the signal, `releaseSeconds` while it is below. Valid times are finite and 0…60 s.
public struct AudioFeatureEnvelope: Sendable, Hashable {
    public var attackSeconds: Double
    public var releaseSeconds: Double

    /// The longest allowed time constant.
    public static let maximumSeconds = 60.0
    /// No smoothing: the signal follows the feature at once.
    public static let none = AudioFeatureEnvelope(attackSeconds: 0, releaseSeconds: 0)
    /// The 10–90 % rise time of a one-pole step, in time constants: ln 9.
    public static let tenToNinetyFactor: Double = log(9.0)

    public init(attackSeconds: Double, releaseSeconds: Double) {
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }

    var isValid: Bool {
        [attackSeconds, releaseSeconds].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= Self.maximumSeconds }
    }

    /// The 10–90 % rise (or 90–10 % fall) time of time constant `timeConstant`.
    public static func riseTime10To90(timeConstant: Double) -> Double { timeConstant * tenToNinetyFactor }

    /// The time constant whose 10–90 % rise time is `riseTime10To90`.
    public static func timeConstant(riseTime10To90: Double) -> Double { riseTime10To90 / tenToNinetyFactor }

    /// One smoothing step from `current` toward `target` over `elapsedSeconds` (contract E2): attack
    /// when the target is above the signal, release otherwise; τ = 0 is instant (even with no elapsed
    /// time); Δt ≤ 0 or non-finite moves nothing; a non-finite target reads 0 and a non-finite signal
    /// snaps to the target. The result is always finite and within 0…1. Pure and allocation-free.
    /// Splitting the elapsed time over several steps gives the same result (frame-rate independent).
    public func step(from current: Double, toward target: Double, elapsedSeconds: Double) -> Double {
        let goal: Double = target.isFinite ? min(max(target, 0), 1) : 0
        guard current.isFinite else { return goal }
        let tau: Double = goal > current ? attackSeconds : releaseSeconds
        guard tau > 0, tau.isFinite else { return goal }
        guard elapsedSeconds > 0, elapsedSeconds.isFinite else { return min(max(current, 0), 1) }
        let next: Double = current + (goal - current) * (1 - exp(-elapsedSeconds / tau))
        return min(max(next, 0), 1)
    }
}

public struct AudioFeatureBinding: Sendable, Hashable {
    public var source: AudioFeatureSource
    public var target: ParameterID
    /// The feature values mapped to signal 0 and 1 (finite, minimum below maximum).
    public var inputMinimum: Double
    public var inputMaximum: Double
    /// The mapped value at signal 0 and at signal 1 (`outputStart > outputEnd` inverts).
    /// Replace: inside the target's range; add: inside ± its span; multiply: inside 0…1.
    public var outputStart: Double
    public var outputEnd: Double
    public var mixMode: ModulationMixMode
    public var envelope: AudioFeatureEnvelope
    /// Shapes the smoothed 0…1 signal before the output range (MOD-004-R6); linear by default.
    public var curve: MappingCurve

    public init(source: AudioFeatureSource, target: ParameterID, inputMinimum: Double = 0, inputMaximum: Double = 1,
                outputStart: Double, outputEnd: Double, mixMode: ModulationMixMode = .replace,
                envelope: AudioFeatureEnvelope = .none, curve: MappingCurve = .linear) {
        self.source = source
        self.target = target
        self.inputMinimum = inputMinimum
        self.inputMaximum = inputMaximum
        self.outputStart = outputStart
        self.outputEnd = outputEnd
        self.mixMode = mixMode
        self.envelope = envelope
        self.curve = curve
    }

    /// The input and output ranges as a linear mapping (MOD-003-R7): exact ends, bounded,
    /// monotonic. Reading and writing it reads and writes the four range fields.
    public var mapping: LinearMapping {
        get { LinearMapping(inputMinimum: inputMinimum, inputMaximum: inputMaximum, outputStart: outputStart, outputEnd: outputEnd) }
        set {
            inputMinimum = newValue.inputMinimum
            inputMaximum = newValue.inputMaximum
            outputStart = newValue.outputStart
            outputEnd = newValue.outputEnd
        }
    }
}

/// Why a binding was refused (contract C2). Bindings are unchanged after any of these.
public enum AudioFeatureBindingError: Error, Sendable, Hashable, CustomStringConvertible {
    case unknownTarget(ParameterID)
    case notNumeric(ParameterID, kind: String)
    case notModulatable(ParameterID)
    case mixModeNotAllowed(ParameterID, ModulationMixMode)
    case bandIndexOutOfRange(ParameterID, Int)
    /// MOD-007: an oscillator index outside 0…`AudioFeatureSource.maximumLFOIndex`.
    case lfoIndexOutOfRange(ParameterID, Int)
    case invalidInputRange(ParameterID)
    case outputOutOfRange(ParameterID, ModulationMixMode, minimum: Double, maximum: Double)
    case invalidEnvelope(ParameterID)
    /// The curve breaks MOD-004 contract K5; `reason` is `MappingCurve.validationProblem`.
    case invalidCurve(ParameterID, reason: String)
    case tooManyBindings(ParameterID, limit: Int)
    /// MOD-011-R1: the target already has `limit` bindings (layers).
    case tooManyLayers(ParameterID, limit: Int)
    /// The binding set would contain a feedback loop (MOD-014-R9); `path` is the loop, readable.
    case feedbackCycle(ParameterID, path: String)

    public var description: String {
        switch self {
        case let .unknownTarget(id):
            "\"\(id)\" is not a registered parameter and cannot be bound"
        case let .notNumeric(id, kind):
            "\"\(id)\" holds a \(kind) value; only continuous and integer parameters can follow audio"
        case let .notModulatable(id):
            "\"\(id)\" is manual only and cannot be modulated"
        case let .mixModeNotAllowed(id, mode):
            "\"\(id)\" does not allow the \(mode.rawValue) mix mode"
        case let .bandIndexOutOfRange(id, index):
            "band \(index) bound to \"\(id)\" is outside 0…\(AudioFeatureSource.maximumBandIndex)"
        case let .lfoIndexOutOfRange(id, index):
            "oscillator \(index) bound to \"\(id)\" is outside 0…\(AudioFeatureSource.maximumLFOIndex)"
        case let .invalidInputRange(id):
            "the input range bound to \"\(id)\" must be finite with its minimum below its maximum"
        case let .outputOutOfRange(id, mode, minimum, maximum):
            "the \(mode.rawValue) output range for \"\(id)\" must lie within \(minimum)…\(maximum)"
        case let .invalidEnvelope(id):
            "the envelope bound to \"\(id)\" needs finite times in 0…\(AudioFeatureEnvelope.maximumSeconds) s"
        case let .invalidCurve(id, reason):
            "the curve bound to \"\(id)\" is invalid: \(reason)"
        case let .tooManyBindings(id, limit):
            "\"\(id)\" cannot be bound: \(limit) bindings already exist"
        case let .tooManyLayers(id, limit):
            "\"\(id)\" cannot take another binding: it already has \(limit), the most per parameter"
        case let .feedbackCycle(id, path):
            "\"\(id)\" cannot be bound: it would create the feedback loop \(path)"
        }
    }
}
