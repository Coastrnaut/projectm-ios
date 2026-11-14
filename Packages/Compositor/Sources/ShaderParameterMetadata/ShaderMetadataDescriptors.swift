// ShaderMetadataDescriptors.swift — validated metadata as MOD-001 descriptors (SHD-003-R5; research
// SHD-003-D3; contracts/shader-parameter-metadata.md M3).
//
// float → continuous with its step hint, modulatable by default; int, bool, enum and color → manual with
// external control allowed (SHD-001's rule for discrete values: no per-frame jumps). The registration site
// is the document and the parameter's position, so a duplicate-ID error names the metadata. Plain Swift.
import ParameterGraph

extension ShaderParameterKind {
    /// The MOD-001 kind.
    public var parameterKind: ParameterKind {
        switch self {
        case let .float(minimum, maximum, step, value):
            return .continuous(minimum: minimum, maximum: maximum, defaultValue: value, step: step)
        case let .int(minimum, maximum, step, value):
            return .integer(minimum: minimum, maximum: maximum, defaultValue: value, step: step)
        case let .bool(value):
            return .boolean(defaultValue: value)
        case let .enumeration(cases, value):
            return .enumeration(cases: cases, defaultValue: value)
        case let .color(value):
            return .color(defaultValue: value)
        }
    }

    public var modulationPolicy: ModulationPolicy {
        if case .float = self { return .continuousDefault }
        return .discreteManual
    }
}

extension ValidatedShaderMetadata {
    /// `<idPrefix>.<parameter>` for every parameter, in slot order.
    public func parameterID(_ spec: ShaderParameterSpec, idPrefix: String) -> ParameterID {
        ParameterID(idPrefix + "." + spec.id)
    }

    /// One MOD-001 descriptor per parameter, in slot order (SHD-003-R5).
    public func descriptors(idPrefix: String, group: ParameterGroup) -> [ParameterDescriptor] {
        parameters.map { (spec: ShaderParameterSpec) -> ParameterDescriptor in
            ParameterDescriptor(id: parameterID(spec, idPrefix: idPrefix), displayName: spec.label, group: group, unit: spec.unit,
                                kind: spec.kind.parameterKind, modulation: spec.kind.modulationPolicy,
                                fileID: "metadata:" + document, line: spec.slot + 1)
        }
    }
}
