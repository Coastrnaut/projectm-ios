// ColorGradeCatalog.swift — FX-003's five grading controls and FX-004's hue as MOD-001 parameters (FX-003-R7; research FX-003-D7;
// specs/123-fx-003-color-grading). Ranges, defaults and step hints are read from `ColorGrade` (single source);
// only IDs, names, the group, units and modulation policies are new here. `ColorGradeCatalogTests` fails on drift.
//
// The app's scene registry and the golden renderer's register these beside `VisualParameterCatalog` and
// `ProceduralMaterialCatalog`, so scene rows and bindings naming them validate, and safety clamps can see them.
// Live modulation is not wired yet (no compositor-backed visual has a modulator).
//
// IDs are permanent: never rename, reuse or re-kind one. To retire an ID, remove its descriptor and add it to
// `retiredIDs`.
import Compositor
import ParameterGraph

/// The stable IDs of the colour grade's parameters.
public enum ColorGradeParameterIDs {
    public static let temperature: ParameterID = "effect.colorGrade.temperature"
    public static let lift: ParameterID = "effect.colorGrade.lift"
    public static let gamma: ParameterID = "effect.colorGrade.gamma"
    public static let gain: ParameterID = "effect.colorGrade.gain"
    public static let saturation: ParameterID = "effect.colorGrade.saturation"
    /// FX-004: degrees around the grey axis.
    public static let hue: ParameterID = "effect.colorGrade.hue"
}

public enum ColorGradeCatalog {
    public static let group = ParameterGroup(id: "effect.colorGrade", displayName: "Color")

    /// IDs that shipped once and may never be registered again (none yet).
    public static let retiredIDs: Set<ParameterID> = []

    /// The catalog, validated (MOD-001-R5).
    public static func makeRegistry() throws(ParameterRegistryError) -> ParameterRegistry {
        try ParameterRegistry(descriptors: descriptors, retiredIDs: retiredIDs)
    }

    /// Every descriptor, in the operators' order (research FX-003-D2; FX-004-D4: hue last).
    public static var descriptors: [ParameterDescriptor] {
        typealias IDs = ColorGradeParameterIDs
        typealias G = ColorGrade
        let neutral: ColorGrade = .neutral
        return [
            descriptor(IDs.temperature, "Temperature (cool to warm)", G.temperatureRange, neutral.temperature, G.temperatureStep),
            descriptor(IDs.lift, "Lift (black level)", G.liftRange, neutral.lift, G.liftStep),
            descriptor(IDs.gamma, "Gamma (mid-tones)", G.gammaRange, neutral.gamma, G.gammaStep),
            descriptor(IDs.gain, "Gain", G.gainRange, neutral.gain, G.gainStep),
            descriptor(IDs.saturation, "Saturation", G.saturationRange, neutral.saturation, G.saturationStep),
            descriptor(IDs.hue, "Hue (degrees)", G.hueRange, neutral.hue, G.hueStep, unit: .degrees),
        ]
    }

    /// The grade of a set of parameter values (missing or non-continuous values → neutral; clamped).
    public static func grade(from values: [ParameterID: ParameterValue]) -> ColorGrade {
        func value(_ id: ParameterID, _ fallback: Double) -> Double {
            if case let .continuous(v)? = values[id] { return v }
            return fallback
        }
        typealias IDs = ColorGradeParameterIDs
        let grade = ColorGrade(temperature: value(IDs.temperature, 0), lift: value(IDs.lift, 0), gamma: value(IDs.gamma, 1),
                               gain: value(IDs.gain, 1), saturation: value(IDs.saturation, 1), hue: value(IDs.hue, 0))
        return grade.clamped
    }

    private static func descriptor(_ id: ParameterID, _ name: String, _ range: ClosedRange<Double>, _ value: Double,
                                   _ step: Double, unit: ParameterUnit = .none, fileID: String = #fileID,
                                   line: Int = #line) -> ParameterDescriptor {
        ParameterDescriptor(id: id, displayName: name, group: group, unit: unit,
                            kind: .continuous(minimum: range.lowerBound, maximum: range.upperBound, defaultValue: value, step: step),
                            modulation: .continuousDefault, fileID: fileID, line: line)
    }
}
