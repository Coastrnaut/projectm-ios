// ProceduralMaterialCatalog.swift — the five curated materials and their documented parameters
// (SHD-001-R1, R2, R3, R9; data-model.md "Parameters"; contracts/material-catalog.md "Catalog").
//
// This file is the single source of truth for every material's IDs, ranges, defaults, units and
// modulation policies; `MaterialCatalogTests` checks it against the data-model table. Bounds keep
// every material safe (SHD-001-R9; research SHD-001-D6): speeds at most one cycle per second in
// magnitude, brightness, contrast and colors at most 1. Continuous parameters are modulatable;
// colors and counts are manual with external control allowed (spec Clarifications).
//
// IDs are permanent: never rename, reuse or re-kind one. To retire an ID, remove its descriptor and
// add it to `retiredIDs`.
import ParameterGraph

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

    // MARK: - The materials

    private static func makeDefinition(_ kind: MaterialKind) -> MaterialDefinition {
        switch kind {
        case .gradient:
            return material(kind, "Two colors blended across the screen, turning slowly.", [
                color(kind, "colorA", "First color", ParameterColor(red: 0.02, green: 0.04, blue: 0.15)),
                color(kind, "colorB", "Second color", ParameterColor(red: 0.30, green: 0.10, blue: 0.40)),
                continuous(kind, "speed", "Rotation (turns per second)", .perSecond, -0.25...0.25, 0.02, step: 0.005),
                brightness(kind, 0.6),
                reactivity(kind),
            ])
        case .plasma:
            return material(kind, "Soft interfering color waves.", [
                continuous(kind, "scale", "Scale (waves across the shorter side)", .none, 0.5...8, 2, step: 0.1),
                continuous(kind, "speed", "Speed (cycles per second)", .perSecond, 0...1, 0.12, step: 0.01),
                brightness(kind, 0.45),
                continuous(kind, "saturation", "Saturation", .normalized, 0...1, 0.6, step: 0.01),
                reactivity(kind),
            ])
        case .noiseFlow:
            return material(kind, "Layered noise in one tint, drifting slowly.", [
                continuous(kind, "scale", "Scale (cells across the shorter side)", .none, 1...16, 4, step: 0.1),
                continuous(kind, "speed", "Drift (cells per second)", .perSecond, 0...1, 0.08, step: 0.01),
                ParameterDescriptor(id: ParameterID("\(kind.id).octaves"), displayName: "Detail (octaves)", group: group(kind),
                                    unit: .count, kind: .integer(minimum: 1, maximum: 5, defaultValue: 3),
                                    modulation: .discreteManual),
                color(kind, "tint", "Tint", ParameterColor(red: 0.10, green: 0.35, blue: 0.45)),
                brightness(kind, 0.6),
                reactivity(kind),
            ])
        case .tunnel:
            return material(kind, "Soft concentric rings moving outward.", [
                continuous(kind, "ringDensity", "Rings (from the center to the shorter edge)", .count, 2...24, 8, step: 0.5),
                continuous(kind, "speed", "Speed (rings per second)", .perSecond, -1...1, 0.1, step: 0.01),
                continuous(kind, "contrast", "Contrast", .normalized, 0...1, 0.35, step: 0.01),
                color(kind, "color", "Color", ParameterColor(red: 0.85, green: 0.45, blue: 0.20)),
                brightness(kind, 0.4),
                reactivity(kind),
            ])
        case .starfield:
            return material(kind, "Small stars drifting across in three depths.", [
                continuous(kind, "density", "Density (of grid cells with a star)", .normalized, 0.05...1, 0.35, step: 0.01),
                continuous(kind, "speed", "Speed (half screens per second)", .perSecond, 0...1, 0.1, step: 0.01),
                continuous(kind, "starSize", "Star size (of a grid cell)", .normalized, 0.1...0.9, 0.35, step: 0.01),
                color(kind, "color", "Color", ParameterColor(red: 0.90, green: 0.90, blue: 1.00)),
                brightness(kind, 0.7),
                reactivity(kind),
            ])
        }
    }

    private static func material(_ kind: MaterialKind, _ summary: String, _ parameters: [ParameterDescriptor]) -> MaterialDefinition {
        MaterialDefinition(kind: kind, displayName: displayName(kind), summary: summary, parameters: parameters)
    }

    private static func group(_ kind: MaterialKind) -> ParameterGroup {
        ParameterGroup(id: kind.id, displayName: displayName(kind))
    }

    private static func displayName(_ kind: MaterialKind) -> String {
        switch kind {
        case .gradient: "Gradient Field"
        case .plasma: "Plasma"
        case .noiseFlow: "Noise Flow"
        case .tunnel: "Ring Tunnel"
        case .starfield: "Starfield"
        }
    }

    private static func continuous(_ kind: MaterialKind, _ name: String, _ displayName: String, _ unit: ParameterUnit,
                                   _ range: ClosedRange<Double>, _ value: Double, step: Double,
                                   fileID: String = #fileID, line: Int = #line) -> ParameterDescriptor {
        ParameterDescriptor(id: ParameterID("\(kind.id).\(name)"), displayName: displayName, group: group(kind), unit: unit,
                            kind: .continuous(minimum: range.lowerBound, maximum: range.upperBound, defaultValue: value, step: step),
                            modulation: .continuousDefault, fileID: fileID, line: line)
    }

    private static func color(_ kind: MaterialKind, _ name: String, _ displayName: String, _ value: ParameterColor,
                              fileID: String = #fileID, line: Int = #line) -> ParameterDescriptor {
        ParameterDescriptor(id: ParameterID("\(kind.id).\(name)"), displayName: displayName, group: group(kind), unit: .none,
                            kind: .color(defaultValue: value), modulation: .discreteManual, fileID: fileID, line: line)
    }

    private static func brightness(_ kind: MaterialKind, _ value: Double, fileID: String = #fileID, line: Int = #line) -> ParameterDescriptor {
        continuous(kind, "brightness", "Brightness", .normalized, 0...1, value, step: 0.01, fileID: fileID, line: line)
    }

    private static func reactivity(_ kind: MaterialKind, fileID: String = #fileID, line: Int = #line) -> ParameterDescriptor {
        continuous(kind, "audioReactivity", "Audio reactivity", .normalized, 0...1, 0.25, step: 0.01, fileID: fileID, line: line)
    }
}
