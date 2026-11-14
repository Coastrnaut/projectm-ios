// AppCoordinator+ParameterInspector.swift — the parameter inspector's live modulation reading (UIX-003-R7, R8;
// research UIX-003-D3). Read on demand by the inspector's 10 Hz timeline only while it is open; nothing here
// is observed per frame. The glow fields report the value the bloom renders (`effectiveGlow`: MIDI live
// value, MOD-002 modulation, then ACC-012's clamp).
import Foundation
import ParameterGraph
import VisualEffects
import VisualParameters

extension AppCoordinator {
    /// What drives `id` right now, or nil when nothing does (or no native visual is running).
    func parameterModulationReading(for id: ParameterID) -> ParameterModulationReading? {
        guard let host = nativeVisual, let descriptor = ParameterInspectorCatalog.descriptor(id),
              let target = ParameterInspectorTargets.target(for: id, settings: settings),
              let manual = target.get().numericValue else { return nil }
        let external: Double? = host.externalValues[id]
        let modulated: Double? = host.modulatorValue(for: id, manual: external ?? manual)
        let rendered: Double? = Self.renderedGlowValue(id, glow: host.effectiveGlow)
        return ParameterModulationReader.reading(descriptor, manual: manual, bindings: host.bindings,
                                                 external: external, modulated: modulated, rendered: rendered)
    }

    /// The rendered value of a glow field, or nil for other parameters.
    static func renderedGlowValue(_ id: ParameterID, glow: BloomParameters) -> Double? {
        switch id {
        case VisualParameterIDs.bloomIntensity: return Double(glow.intensity)
        case VisualParameterIDs.bloomRadius: return Double(glow.radius)
        case VisualParameterIDs.bloomThreshold: return Double(glow.threshold)
        case VisualParameterIDs.bloomKnee: return Double(glow.knee)
        default: return nil
        }
    }
}
