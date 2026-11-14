// MotionFeedbackCatalog.swift — FX-009's Trails as MOD-001 parameters (FX-009-R10; research FX-009-D8;
// specs/130-fx-009-motion-feedback). Range, default and step hint are read from `MotionFeedback` (single source);
// `ColorGradeCatalogTests` fails on drift. Kept beside the colour grade's catalog: both are the compositor output
// pass's parameters, so no new target.
//
// The app's scene registry and the golden renderer's register these beside `ColorGradeCatalog`, so scene rows and
// bindings naming them validate and safety clamps can see them. Live modulation is not wired yet (no
// compositor-backed visual has a modulator).
//
// IDs are permanent: never rename, reuse or re-kind one. To retire an ID, remove its descriptor and add it to
// `retiredIDs`.
import Compositor
import ParameterGraph

/// The stable IDs of the Trails parameters.
public enum MotionFeedbackParameterIDs {
    public static let enabled: ParameterID = "effect.feedback.enabled"
    /// Seconds for a trail to fade to half.
    public static let halfLife: ParameterID = "effect.feedback.halfLife"
}

public enum MotionFeedbackCatalog {
    public static let group = ParameterGroup(id: "effect.feedback", displayName: "Trails")

    /// IDs that shipped once and may never be registered again (none yet).
    public static let retiredIDs: Set<ParameterID> = []

    /// The catalog, validated (MOD-001-R5).
    public static func makeRegistry() throws(ParameterRegistryError) -> ParameterRegistry {
        try ParameterRegistry(descriptors: descriptors, retiredIDs: retiredIDs)
    }

    public static var descriptors: [ParameterDescriptor] {
        let range: ClosedRange<Double> = MotionFeedback.halfLifeRange
        let halfLife = ParameterDescriptor(id: MotionFeedbackParameterIDs.halfLife, displayName: "Trails length", group: group,
                                           unit: .seconds,
                                           kind: .continuous(minimum: range.lowerBound, maximum: range.upperBound,
                                                             defaultValue: MotionFeedback.defaultHalfLife,
                                                             step: MotionFeedback.halfLifeStep),
                                           modulation: .continuousDefault)
        let enabled = ParameterDescriptor(id: MotionFeedbackParameterIDs.enabled, displayName: "Trails", group: group,
                                          unit: .none, kind: .boolean(defaultValue: false), modulation: .discreteManual)
        return [enabled, halfLife]
    }

    /// The Trails value of a set of parameter values (missing or mistyped → off / the default length; clamped).
    public static func feedback(from values: [ParameterID: ParameterValue]) -> MotionFeedback {
        var feedback = MotionFeedback.off
        if case let .boolean(on)? = values[MotionFeedbackParameterIDs.enabled] { feedback.isEnabled = on }
        if case let .continuous(seconds)? = values[MotionFeedbackParameterIDs.halfLife] { feedback.halfLifeSeconds = seconds }
        return feedback.clamped
    }
}
