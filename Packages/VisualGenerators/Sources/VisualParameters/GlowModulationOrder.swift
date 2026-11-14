// GlowModulationOrder.swift — the glow's whole modulation order after its base value, in one place
// (MOD-011-R5, R6; contract specs/178-mod-011-mix-modes/contracts/mix-order.md O1 steps 2 to 4; research
// MOD-011-D5). The native spectrum host calls it each time the glow is resolved.
//
//   base (the caller's: Settings/macro/snapshot value, or MIDI-003's live value while one exists)
//   → every binding of the intensity, in list order, clamped to 0…1 after each (`ModulationMixOrder`)
//   → ACC-012 excursion scaling from the base (`SafetyClamp.modulated`)
//   → ACC-012's intensity cap (`BloomParameters.limited(by:)`), last.
//
// Unbound, only the cap applies (bit-identical to FX-001 at the Standard profile). Allocation-free.
import FlashSafety
import ParameterGraph
import VisualEffects

public enum GlowModulationOrder {
    /// The glow the bloom renders, from `base` (MIDI live values already applied).
    public static func resolve(base: BloomParameters, modulator: AudioFeatureModulator?, clamp: SafetyClamp) -> BloomParameters {
        var resolved: BloomParameters = base
        let id: ParameterID = VisualParameterIDs.bloomIntensity
        if let modulator, modulator.isBound(id) {
            let manual: Double = Double(resolved.intensity)
            let modulated: Double = modulator.value(for: id, manual: manual)
            resolved.intensity = Float(clamp.modulated(manual: manual, modulated: modulated))   // ACC-012: depth
        }
        return resolved.limited(by: clamp)   // ACC-012-R4: the cap, after modulation, before render
    }
}
