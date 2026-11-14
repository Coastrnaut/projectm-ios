// MaterialDefinition.swift — what one curated procedural material is (SHD-001-R1, R2; data-model.md
// "MaterialKind", "MaterialDefinition"; contracts/material-catalog.md "Catalog").
//
// A material is authored in this module: its parameters are MOD-001 descriptors, parameter i is
// uniform slot i of the shader (a float4: scalars in .x, colors as RGBA), and its fragment function
// is a named entry point of `ProceduralMaterialShaders.source`. Plain Swift; builds on Linux.
import ParameterGraph
import ShaderParameterMetadata

/// The curated materials, in catalog order. The raw value is the material's name (its ID's second
/// segment); IDs are permanent.
public enum MaterialKind: String, CaseIterable, Sendable {
    case gradient
    case plasma
    case noiseFlow
    case tunnel
    case starfield

    /// `material.<name>`.
    public var id: String { "material.\(rawValue)" }
}

public struct MaterialDefinition: Sendable, Hashable {
    /// The most parameters (uniform slots) a material may have.
    public static let maximumParameterCount = 8

    public let kind: MaterialKind
    public let displayName: String
    /// One line for people.
    public let summary: String
    /// Ordered; parameter i is uniform slot i.
    public let parameters: [ParameterDescriptor]
    /// SHD-003: the validated metadata the parameters were built from (nil for a hand-made definition).
    public let metadata: ValidatedShaderMetadata?

    public init(kind: MaterialKind, displayName: String, summary: String, parameters: [ParameterDescriptor]) {
        self.kind = kind
        self.displayName = displayName
        self.summary = summary
        self.parameters = parameters
        metadata = nil
    }

    /// SHD-003-R5: a material whose name, summary and parameters come from its validated metadata.
    public init(kind: MaterialKind, metadata: ValidatedShaderMetadata) {
        self.kind = kind
        displayName = metadata.name
        summary = metadata.summary
        parameters = metadata.descriptors(idPrefix: kind.id, group: ParameterGroup(id: kind.id, displayName: metadata.name))
        self.metadata = metadata
    }

    /// `material.<name>`.
    public var id: String { kind.id }

    /// The group every parameter of this material belongs to.
    public var group: ParameterGroup { ParameterGroup(id: kind.id, displayName: displayName) }

    /// The shader entry point (`mat_<name>`) of the default variant.
    public var fragmentFunction: String { "mat_\(kind.rawValue)" }

    /// SHD-004-R1: the material's precompiled implementations, default first (one "Standard" variant for a
    /// hand-made definition).
    public var variants: [ShaderVariantSpec] {
        metadata?.variants ?? [ShaderVariantSpec(id: kind.rawValue, label: ShaderMetadataReader.defaultVariantLabel)]
    }

    /// The default variant's ID (`<name>`).
    public var defaultVariantID: String { variants.first?.id ?? kind.rawValue }

    /// The variant whose ID is exactly `id`, or nil.
    public func variant(_ id: String) -> ShaderVariantSpec? { variants.first { $0.id == id } }

    /// SHD-004-R2: a variant's entry point, `mat_<variant id>`.
    public func fragmentFunction(for variantID: String) -> String { "mat_" + variantID }

    /// `material.<name>.<parameter>`.
    public func parameterID(_ name: String) -> ParameterID { ParameterID("\(kind.id).\(name)") }

    /// Every material has a speed (cycles per second) and an audio reactivity (0…1).
    public var speedParameter: ParameterID { parameterID("speed") }
    public var reactivityParameter: ParameterID { parameterID("audioReactivity") }

    /// The slot of `id`, or nil.
    public func slot(of id: ParameterID) -> Int? { parameters.firstIndex { $0.id == id } }
}

extension MaterialDefinition {
    /// SHD-003-R7: the inspector controls of this material, built from its validated metadata alone (empty for
    /// a hand-made definition without metadata).
    public func controls(values: [ParameterID: ParameterValue]) -> [ShaderParameterControl] {
        guard let metadata else { return [] }
        return ShaderParameterControls.controls(for: metadata, idPrefix: kind.id, group: group, values: values)
    }
}
