// MaterialDefinition.swift — what one curated procedural material is (SHD-001-R1, R2; data-model.md
// "MaterialKind", "MaterialDefinition"; contracts/material-catalog.md "Catalog").
//
// A material is authored in this module: its parameters are MOD-001 descriptors, parameter i is
// uniform slot i of the shader (a float4: scalars in .x, colors as RGBA), and its fragment function
// is a named entry point of `ProceduralMaterialShaders.source`. Plain Swift; builds on Linux.
import ParameterGraph

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

    public init(kind: MaterialKind, displayName: String, summary: String, parameters: [ParameterDescriptor]) {
        self.kind = kind
        self.displayName = displayName
        self.summary = summary
        self.parameters = parameters
    }

    /// `material.<name>`.
    public var id: String { kind.id }

    /// The group every parameter of this material belongs to.
    public var group: ParameterGroup { ParameterGroup(id: kind.id, displayName: displayName) }

    /// The shader entry point (`mat_<name>`).
    public var fragmentFunction: String { "mat_\(kind.rawValue)" }

    /// `material.<name>.<parameter>`.
    public func parameterID(_ name: String) -> ParameterID { ParameterID("\(kind.id).\(name)") }

    /// Every material has a speed (cycles per second) and an audio reactivity (0…1).
    public var speedParameter: ParameterID { parameterID("speed") }
    public var reactivityParameter: ParameterID { parameterID("audioReactivity") }

    /// The slot of `id`, or nil.
    public func slot(of id: ParameterID) -> Int? { parameters.firstIndex { $0.id == id } }
}
