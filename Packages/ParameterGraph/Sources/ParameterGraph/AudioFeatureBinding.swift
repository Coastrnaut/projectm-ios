// AudioFeatureBinding.swift — one audio feature bound to one parameter, and why a binding is
// refused (MOD-002-R2 to R4; research MOD-002-D4, D5; contract C2).
//
// A binding maps the feature's position in the input range (0…1, clamped) to the output range,
// optionally smoothed by an attack/release envelope, and combines it with the parameter's manual
// value by the mix mode. `AudioFeatureModulator.bind` validates it against the registry.

/// Rise and fall time constants of a one-pole envelope, in seconds; 0 means no smoothing.
public struct AudioFeatureEnvelope: Sendable, Hashable {
    public var attackSeconds: Double
    public var releaseSeconds: Double

    /// The longest allowed time constant.
    public static let maximumSeconds = 60.0
    /// No smoothing: the signal follows the feature at once.
    public static let none = AudioFeatureEnvelope(attackSeconds: 0, releaseSeconds: 0)

    public init(attackSeconds: Double, releaseSeconds: Double) {
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }

    var isValid: Bool {
        [attackSeconds, releaseSeconds].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= Self.maximumSeconds }
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

    public init(source: AudioFeatureSource, target: ParameterID, inputMinimum: Double = 0, inputMaximum: Double = 1,
                outputStart: Double, outputEnd: Double, mixMode: ModulationMixMode = .replace,
                envelope: AudioFeatureEnvelope = .none) {
        self.source = source
        self.target = target
        self.inputMinimum = inputMinimum
        self.inputMaximum = inputMaximum
        self.outputStart = outputStart
        self.outputEnd = outputEnd
        self.mixMode = mixMode
        self.envelope = envelope
    }
}

/// Why a binding was refused (contract C2). Bindings are unchanged after any of these.
public enum AudioFeatureBindingError: Error, Sendable, Hashable, CustomStringConvertible {
    case unknownTarget(ParameterID)
    case notNumeric(ParameterID, kind: String)
    case notModulatable(ParameterID)
    case mixModeNotAllowed(ParameterID, ModulationMixMode)
    case bandIndexOutOfRange(ParameterID, Int)
    case invalidInputRange(ParameterID)
    case outputOutOfRange(ParameterID, ModulationMixMode, minimum: Double, maximum: Double)
    case invalidEnvelope(ParameterID)
    case tooManyBindings(ParameterID, limit: Int)

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
        case let .invalidInputRange(id):
            "the input range bound to \"\(id)\" must be finite with its minimum below its maximum"
        case let .outputOutOfRange(id, mode, minimum, maximum):
            "the \(mode.rawValue) output range for \"\(id)\" must lie within \(minimum)…\(maximum)"
        case let .invalidEnvelope(id):
            "the envelope bound to \"\(id)\" needs finite times in 0…\(AudioFeatureEnvelope.maximumSeconds) s"
        case let .tooManyBindings(id, limit):
            "\"\(id)\" cannot be bound: \(limit) bindings already exist"
        }
    }
}
