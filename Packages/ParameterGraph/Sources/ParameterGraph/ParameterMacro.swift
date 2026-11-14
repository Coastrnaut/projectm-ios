// ParameterMacro.swift — one normalized value drives several registry parameters, each through its own
// MOD-004 curve and MOD-003 range (MOD-010-R1 to R5, R11; research MOD-010-D1;
// specs/170-mod-010-parameter-macro/contracts/parameter-macro.md M1, M2).
//
// * Target value: `range.interpolate(curve.apply(inverted ? 1 − m : m))`, limited to the parameter's
//   registry range. Exact at m = 0 and 1 (MOD-004 pins the ends, MOD-003 interpolates them exactly).
// * Kinds: continuous; integer (nearest step from the minimum); enum (the range is in case positions, the
//   nearest case wins). On/off and color parameters are refused.
// * `evaluate` never traps: unknown, unsupported, invalid, duplicate and beyond-limit targets are skipped with a
//   reason; the other targets apply. Pure and deterministic; plain Swift (no Foundation), so it builds on Linux.
// * The app writes the assignments as base values through the Settings path (research MOD-010-D2).

/// One parameter a macro drives.
public struct MacroTarget: Sendable, Hashable {
    public var parameter: ParameterID
    public var curve: MappingCurve
    /// The value (enum: case position) at curve output 0; nil = the parameter's minimum (enum: 0).
    public var outputMinimum: Double?
    /// The value (enum: case position) at curve output 1; nil = the parameter's maximum (enum: last case).
    public var outputMaximum: Double?
    /// Reads the macro as 1 − value.
    public var inverted: Bool

    public init(parameter: ParameterID, curve: MappingCurve = .linear, outputMinimum: Double? = nil,
                outputMaximum: Double? = nil, inverted: Bool = false) {
        self.parameter = parameter
        self.curve = curve
        self.outputMinimum = outputMinimum
        self.outputMaximum = outputMaximum
        self.inverted = inverted
    }
}

/// Why a target is not applied (contract M2).
public enum MacroProblem: Sendable, Hashable, CustomStringConvertible {
    case unknownParameter
    /// The kind name ("boolean", "color").
    case unsupportedKind(String)
    /// MOD-004's validation clause.
    case invalidCurve(String)
    case invalidRange
    case duplicateParameter
    case beyondLimit

    public var description: String {
        switch self {
        case .unknownParameter: return "the parameter is not known to this version"
        case let .unsupportedKind(kind): return "a macro cannot drive a parameter of kind \(kind)"
        case let .invalidCurve(reason): return "the curve is invalid: \(reason)"
        case .invalidRange: return "the range must be finite with minimum ≤ maximum"
        case .duplicateParameter: return "an earlier target already drives this parameter"
        case .beyondLimit: return "a macro uses at most \(ParameterMacro.maximumTargets) targets"
        }
    }
}

/// One value a macro sets.
public struct MacroAssignment: Sendable, Hashable {
    public let parameter: ParameterID
    public let value: ParameterValue

    public init(parameter: ParameterID, value: ParameterValue) {
        self.parameter = parameter
        self.value = value
    }
}

/// One target that was not applied, by its index in `targets`.
public struct MacroSkip: Sendable, Hashable {
    public let index: Int
    public let parameter: ParameterID
    public let problem: MacroProblem

    public init(index: Int, parameter: ParameterID, problem: MacroProblem) {
        self.index = index
        self.parameter = parameter
        self.problem = problem
    }
}

public struct MacroEvaluation: Sendable, Hashable {
    public var assignments: [MacroAssignment]
    public var skipped: [MacroSkip]
}

public struct ParameterMacro: Sendable, Hashable {
    /// Targets used per macro; later ones are skipped (`beyondLimit`).
    public static let maximumTargets: Int = 8
    /// Macros used per scene (SceneFormat keeps more, unused).
    public static let maximumMacros: Int = 8

    public var name: String
    /// Read limited to 0…1 (non-finite → 0).
    public var value: Double
    public var targets: [MacroTarget]

    public init(name: String, value: Double = 0, targets: [MacroTarget] = []) {
        self.name = name
        self.value = value
        self.targets = targets
    }

    /// `value` limited to 0…1; non-finite reads 0 (MOD-003's position rule).
    public var normalizedValue: Double { LinearMapping.clampedPosition(value) }

    /// The values the macro sets at `value` (default: its own) and the targets it skips, in target order.
    public func evaluate(at value: Double? = nil, registry: ParameterRegistry) -> MacroEvaluation {
        let m: Double = LinearMapping.clampedPosition(value ?? self.value)
        var assignments: [MacroAssignment] = []
        var skipped: [MacroSkip] = []
        var seen: Set<ParameterID> = []
        for (index, target) in targets.enumerated() {
            let problem: MacroProblem? = Self.problem(target, index: index, seen: seen, registry: registry)
            if let problem {
                skipped.append(MacroSkip(index: index, parameter: target.parameter, problem: problem))
                continue
            }
            seen.insert(target.parameter)
            guard let descriptor = registry.descriptor(for: target.parameter),
                  let result = target.value(at: m, descriptor: descriptor) else { continue }
            assignments.append(MacroAssignment(parameter: target.parameter, value: result))
        }
        return MacroEvaluation(assignments: assignments, skipped: skipped)
    }

    private static func problem(_ target: MacroTarget, index: Int, seen: Set<ParameterID>,
                                registry: ParameterRegistry) -> MacroProblem? {
        if index >= maximumTargets { return .beyondLimit }
        if let problem = target.problem(descriptor: registry.descriptor(for: target.parameter)) { return problem }
        if seen.contains(target.parameter) { return .duplicateParameter }
        return nil
    }
}

extension MacroTarget {
    /// Nil when the target can drive `descriptor` (nil descriptor: unknown parameter).
    public func problem(descriptor: ParameterDescriptor?) -> MacroProblem? {
        guard let descriptor else { return .unknownParameter }
        switch descriptor.kind {
        case .boolean, .color: return .unsupportedKind(descriptor.kind.name)
        case .continuous, .integer, .enumeration: break
        }
        if let reason = curve.validationProblem { return .invalidCurve(reason) }
        let lower: Double? = outputMinimum
        let upper: Double? = outputMaximum
        if let lower, !lower.isFinite { return .invalidRange }
        if let upper, !upper.isFinite { return .invalidRange }
        if let lower, let upper, lower > upper { return .invalidRange }
        return nil
    }

    /// The curve's output (0…1) at macro value `m` (limited first; reversed when `inverted`).
    public func shapedPosition(at m: Double) -> Double {
        let limited: Double = LinearMapping.clampedPosition(m)
        let input: Double = inverted ? 1 - limited : limited
        return curve.apply(input)
    }

    /// The parameter value at macro value `m` (contract M1); nil for a kind a macro cannot drive.
    public func value(at m: Double, descriptor: ParameterDescriptor) -> ParameterValue? {
        let position: Double = shapedPosition(at: m)
        switch descriptor.kind {
        case let .continuous(minimum, maximum, _, _, _):
            let x: Double = interpolate(position, lower: minimum, upper: maximum)
            return .continuous(Self.limit(x, minimum, maximum))
        case let .integer(minimum, maximum, _, step):
            let low: Double = Double(minimum)
            let high: Double = Double(maximum)
            let x: Double = Self.limit(interpolate(position, lower: low, upper: high), low, high)
            let stride: Double = Double(max(step, 1))
            let steps: Double = ((x - low) / stride).rounded(.toNearestOrAwayFromZero)
            let snapped: Double = Self.limit(low + steps * stride, low, high)
            return .integer(Int(snapped))
        case let .enumeration(cases, _):
            guard !cases.isEmpty else { return nil }
            let last: Double = Double(cases.count - 1)
            let x: Double = Self.limit(interpolate(position, lower: 0, upper: last), 0, last)
            let index: Int = Int(x.rounded(.toNearestOrAwayFromZero))
            return .enumeration(cases[index].id)
        case .boolean, .color:
            return nil
        }
    }

    private func interpolate(_ position: Double, lower: Double, upper: Double) -> Double {
        let start: Double = outputMinimum ?? lower
        let end: Double = outputMaximum ?? upper
        return LinearMapping.interpolate(from: start, to: end, at: position)
    }

    private static func limit(_ x: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(x, lower), upper)
    }
}
