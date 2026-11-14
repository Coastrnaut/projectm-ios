// ProceduralMaterialCatalog.swift — the five curated materials and their documented parameters
// (SHD-001-R1, R2, R3, R9; data-model.md "Parameters"; contracts/material-catalog.md "Catalog").
//
// SHD-003: every material's IDs, ranges, defaults, units and enum cases live in its metadata document
// (MaterialParameterMetadata.swift); this file validates them and builds the MOD-001 descriptors (float →
// modulatable, everything else manual). `MaterialCatalogTests` checks the result against the data-model table. Bounds keep
// every material safe (SHD-001-R9; research SHD-001-D6): speeds at most one cycle per second in
// magnitude, brightness, contrast and colors at most 1. Continuous parameters are modulatable;
// colors and counts are manual with external control allowed (spec Clarifications).
//
// IDs are permanent: never rename, reuse or re-kind one. To retire an ID, remove its descriptor and
// add it to `retiredIDs`.
import ParameterGraph
import ShaderParameterMetadata

public enum ProceduralMaterialCatalog {
    /// IDs that shipped once and may never be registered again (none yet).
    public static let retiredIDs: Set<ParameterID> = []

    /// Every material, in catalog order (SHD-001-R1).
    public static let materials: [MaterialDefinition] = MaterialKind.allCases.map { (kind: MaterialKind) -> MaterialDefinition in
        makeDefinition(kind)
    }

    /// The definition of `kind`.
    public static func definition(_ kind: MaterialKind) -> MaterialDefinition {
        materials[MaterialKind.allCases.firstIndex(of: kind) ?? 0]
    }

    /// The material whose ID is exactly `id`, or nil (SHD-001-R3). No material is ever made from
    /// other text.
    public static func material(withID id: String) -> MaterialDefinition? {
        materials.first { $0.id == id }
    }

    /// Every material's parameters, in catalog order.
    public static var descriptors: [ParameterDescriptor] {
        materials.flatMap { (m: MaterialDefinition) -> [ParameterDescriptor] in m.parameters }
    }

    /// The catalog, validated (MOD-001-R5). Throws only if a descriptor here is malformed, which
    /// `MaterialCatalogTests` rules out in CI.
    public static func makeRegistry() throws(ParameterRegistryError) -> ParameterRegistry {
        try ParameterRegistry(descriptors: descriptors, retiredIDs: retiredIDs)
    }

    /// The documented default of every parameter of `kind`.
    public static func defaultValues(for kind: MaterialKind) -> [ParameterID: ParameterValue] {
        var values: [ParameterID: ParameterValue] = [:]
        for d in definition(kind).parameters { values[d.id] = d.defaultValue }
        return values
    }

    // MARK: - The materials (SHD-003: built from validated metadata)

    /// The validated metadata of `kind` (SHD-003-R1 to R3). The documents are module constants checked by
    /// `MaterialMetadataTests` in CI, so a failure here is a programming error.
    public static func metadata(_ kind: MaterialKind) -> ValidatedShaderMetadata {
        do {
            return try ShaderMetadataReader.validate(json: MaterialParameterMetadata.json(kind), document: kind.id,
                                                     requiredParameters: MaterialParameterMetadata.requiredParameters)
        } catch {
            preconditionFailure("SHD-003: bundled metadata is invalid: \(error)")
        }
    }

    private static func makeDefinition(_ kind: MaterialKind) -> MaterialDefinition {
        let validated: ValidatedShaderMetadata = metadata(kind)
        precondition(validated.variant == kind.rawValue, "SHD-003: \(kind.id) metadata names variant \(validated.variant)")
        return MaterialDefinition(kind: kind, metadata: validated)
    }
}
