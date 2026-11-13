// MaterialParameterValues.swift — the current, clamped parameter values of one material
// (SHD-001-R6; research SHD-001-D3, D4; data-model.md "MaterialParameterValues").
//
// The same rules as MOD-001's store (contract C3.2) without its lock, so the compositor thread can
// read the values in `render`: numbers clamped to the range (integers also snapped to the step),
// colors clamped per component; non-finite numbers, unknown IDs, values of another kind and unknown
// enum cases are refused and the stored value stays. Slot i (a float4) is parameter i as the shader
// reads it. Plain Swift; builds on Linux.
import ParameterGraph

public enum MaterialParameterError: Error, Sendable, Equatable {
    case unknownParameter(ParameterID)
    case nonFiniteValue(ParameterID)
    case kindMismatch(ParameterID, expected: String, got: String)
    case unknownEnumCase(ParameterID, String)
}

public struct MaterialParameterValues: Sendable, Equatable {
    public let definition: MaterialDefinition
    /// In parameter (slot) order.
    public private(set) var values: [ParameterValue]
    /// The shader's view of `values`, kept in step by `set`.
    private var slots: [SIMD4<Float>]

    /// Every parameter at its documented default.
    public init(_ definition: MaterialDefinition) {
        self.definition = definition
        values = definition.parameters.map { (d: ParameterDescriptor) -> ParameterValue in d.defaultValue }
        slots = definition.parameters.map { (d: ParameterDescriptor) -> SIMD4<Float> in Self.encode(d.defaultValue, kind: d.kind) }
    }

    public func value(for id: ParameterID) -> ParameterValue? {
        definition.slot(of: id).map { values[$0] }
    }

    /// A numeric parameter as a Double (nil for other kinds or unknown IDs).
    public func double(_ id: ParameterID) -> Double? {
        switch value(for: id) {
        case let .continuous(v)?: v
        case let .integer(v)?: Double(v)
        default: nil
        }
    }

    /// Stores `value` clamped and returns what was stored; throws and keeps the stored value when it
    /// is refused.
    @discardableResult
    public mutating func set(_ value: ParameterValue, for id: ParameterID) throws(MaterialParameterError) -> ParameterValue {
        guard let index = definition.slot(of: id) else { throw .unknownParameter(id) }
        let descriptor = definition.parameters[index]
        let stored = try Self.normalized(value, for: descriptor)
        values[index] = stored
        slots[index] = Self.encode(stored, kind: descriptor.kind)
        return stored
    }

    /// Uniform slot `index` (zero beyond the parameters).
    public func slot(_ index: Int) -> SIMD4<Float> {
        index >= 0 && index < slots.count ? slots[index] : .zero
    }

    // MARK: - Rules

    static func normalized(_ value: ParameterValue, for d: ParameterDescriptor) throws(MaterialParameterError) -> ParameterValue {
        switch (d.kind, value) {
        case let (.continuous(minimum, maximum, _, _, _), .continuous(v)):
            guard v.isFinite else { throw .nonFiniteValue(d.id) }
            return .continuous(min(max(v, minimum), maximum))
        case let (.integer(minimum, maximum, _, step), .integer(v)):
            let clamped = min(max(v, minimum), maximum)
            let step = max(step, 1)
            let lastStep = (maximum - minimum) / step
            let nearest = min((clamped - minimum + step / 2) / step, lastStep)
            return .integer(minimum + nearest * step)
        case (.boolean, .boolean):
            return value
        case let (.enumeration(cases, _), .enumeration(caseID)):
            guard cases.contains(where: { $0.id == caseID }) else { throw .unknownEnumCase(d.id, caseID) }
            return value
        case let (.color, .color(c)):
            guard c.isFinite else { throw .nonFiniteValue(d.id) }
            return .color(c.clamped)
        default:
            throw .kindMismatch(d.id, expected: d.kind.name, got: value.kindName)
        }
    }

    static func encode(_ value: ParameterValue, kind: ParameterKind) -> SIMD4<Float> {
        switch value {
        case let .continuous(v): return SIMD4(Float(v), 0, 0, 0)
        case let .integer(v): return SIMD4(Float(v), 0, 0, 0)
        case let .boolean(v): return SIMD4(v ? 1 : 0, 0, 0, 0)
        case let .color(c): return SIMD4(Float(c.red), Float(c.green), Float(c.blue), Float(c.alpha))
        case let .enumeration(caseID):
            if case let .enumeration(cases, _) = kind, let i = cases.firstIndex(where: { $0.id == caseID }) {
                return SIMD4(Float(i), 0, 0, 0)
            }
            return .zero
        }
    }
}
