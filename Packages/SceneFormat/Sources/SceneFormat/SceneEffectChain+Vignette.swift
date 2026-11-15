// SceneEffectChain+Vignette.swift — FX-015: the `fx.vignette` entry of the FX-020 `effects` list
// (specs/305-fx-015-vignette, contracts/vignette.md C3, research FX-015-D6; ADR-0116).
//
// Parameters: `intensity` (0…1), `softness` (0.1…0.9), `centerX` and `centerY` (0…1 of the width and height). Missing →
// the default; not a number or out of range → default or nearest bound, reported. The entry is written only while the
// vignette is on (a disabled vignette is default), so older scenes encode byte-identically.
import Compositor

extension SceneEffectSettings {
    static let vignetteParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "intensity", range: Vignette.intensityRange, fallback: Vignette.defaultIntensity),
        SceneEffectParameter(name: "softness", range: Vignette.softnessRange, fallback: Vignette.defaultSoftness),
        SceneEffectParameter(name: "centerX", range: Vignette.centerRange, fallback: Vignette.defaultCenter),
        SceneEffectParameter(name: "centerY", range: Vignette.centerRange, fallback: Vignette.defaultCenter),
    ]

    static func readVignette(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> Vignette {
        let v: [Double] = values(entry, vignetteParameters, path, &issues)
        return Vignette(isEnabled: entry.enabled, intensity: v[0], softness: v[1], centerX: v[2], centerY: v[3])
    }

    static func writeVignette(_ vignette: Vignette, into entry: inout SceneEffectEntry) {
        entry.enabled = vignette.isEnabled
        entry.parameters["intensity"] = .double(vignette.intensity)
        entry.parameters["softness"] = .double(vignette.softness)
        entry.parameters["centerX"] = .double(vignette.centerX)
        entry.parameters["centerY"] = .double(vignette.centerY)
    }
}
