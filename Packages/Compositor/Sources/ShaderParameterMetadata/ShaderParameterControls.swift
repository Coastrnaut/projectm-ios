// ShaderParameterControls.swift — inspector controls built from validated metadata alone (SHD-003-R7;
// research SHD-003-D5; contracts/shader-parameter-metadata.md M4).
//
// One control per parameter, in slot order: slider (float), stepper (int), picker (enum), toggle (bool),
// color (color). Nothing here names a particular shader or parameter. The shown value is the stored value
// when it fits the parameter (kind, finite, a known case; numbers clamped to the range, integers snapped
// to the step as the layer would store them), else the default. Plain Swift; builds on Linux.
import ParameterGraph

public struct ShaderParameterControl: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case slider, stepper, picker, toggle, color
    }

    /// The MOD-001 descriptor the control edits (ID, label, unit, range, step, default).
    public let descriptor: ParameterDescriptor
    public let kind: Kind
    /// Numbers only.
    public let range: ClosedRange<Double>?
    /// Numbers only.
    public let step: Double?
    /// Pickers only, in order.
    public let options: [ParameterEnumCase]
    public let value: ParameterValue

    public var id: ParameterID { descriptor.id }
    public var label: String { descriptor.displayName }
    public var unit: ParameterUnit { descriptor.unit }
    public var defaultValue: ParameterValue { descriptor.defaultValue }
}

public enum ShaderParameterControls {
    /// The controls of `metadata` with `values` (missing or unfitting values show the default).
    public static func controls(for metadata: ValidatedShaderMetadata, idPrefix: String, group: ParameterGroup,
                                values: [ParameterID: ParameterValue]) -> [ShaderParameterControl] {
        let descriptors: [ParameterDescriptor] = metadata.descriptors(idPrefix: idPrefix, group: group)
        var controls: [ShaderParameterControl] = []
        controls.reserveCapacity(descriptors.count)
        for (spec, descriptor) in zip(metadata.parameters, descriptors) {
            controls.append(control(spec, descriptor: descriptor, stored: values[descriptor.id]))
        }
        return controls
    }

    static func control(_ spec: ShaderParameterSpec, descriptor: ParameterDescriptor, stored: ParameterValue?) -> ShaderParameterControl {
        let value: ParameterValue = shown(stored, kind: spec.kind) ?? descriptor.defaultValue
        switch spec.kind {
        case let .float(minimum, maximum, step, _):
            return ShaderParameterControl(descriptor: descriptor, kind: .slider, range: minimum...maximum, step: step, options: [], value: value)
        case let .int(minimum, maximum, step, _):
            return ShaderParameterControl(descriptor: descriptor, kind: .stepper, range: Double(minimum)...Double(maximum),
                                          step: Double(step), options: [], value: value)
        case .bool:
            return ShaderParameterControl(descriptor: descriptor, kind: .toggle, range: nil, step: nil, options: [], value: value)
        case let .enumeration(cases, _):
            return ShaderParameterControl(descriptor: descriptor, kind: .picker, range: nil, step: nil, options: cases, value: value)
        case .color:
            return ShaderParameterControl(descriptor: descriptor, kind: .color, range: nil, step: nil, options: [], value: value)
        }
    }

    /// `stored` as the layer would hold it, or nil when it does not fit `kind`.
    static func shown(_ stored: ParameterValue?, kind: ShaderParameterKind) -> ParameterValue? {
        guard let stored else { return nil }
        switch (kind, stored) {
        case let (.float(minimum, maximum, _, _), .continuous(v)):
            return v.isFinite ? .continuous(min(max(v, minimum), maximum)) : nil
        case let (.int(minimum, maximum, step, _), .integer(v)):
            let clamped: Int = min(max(v, minimum), maximum)
            let steps: Int = min((clamped - minimum + step / 2) / step, (maximum - minimum) / step)
            return .integer(minimum + steps * step)
        case (.bool, .boolean):
            return stored
        case let (.enumeration(cases, _), .enumeration(id)):
            return cases.contains { (c: ParameterEnumCase) -> Bool in c.id == id } ? stored : nil
        case let (.color, .color(c)):
            return c.isFinite ? .color(c.clamped) : nil
        default:
            return nil
        }
    }
}
