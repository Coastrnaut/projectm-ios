// SceneEffectChain+LensDistortion.swift — FX-016: the `fx.lensDistortion` entry of the FX-020 `effects` list
// (specs/306-fx-016-lens-distortion, contracts/lens-distortion.md C3, research FX-016-D7; ADR-0117).
//
// Parameters: `strength` (−1…1; positive barrel, negative pincushion) and `zoomToFill` (0 or 1; ≥ 0.5 reads as on, like
// FX-014's `mode`). Missing → the default; not a number or out of range → default or nearest bound, reported. The entry
// is written only while the warp is on (a disabled warp is default), so older scenes encode byte-identically.
import Compositor

extension SceneEffectSettings {
    static let lensDistortionParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "strength", range: LensDistortion.strengthRange, fallback: LensDistortion.defaultStrength),
        SceneEffectParameter(name: "zoomToFill", range: 0...1, fallback: 1),
    ]

    static func readLensDistortion(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> LensDistortion {
        let v: [Double] = values(entry, lensDistortionParameters, path, &issues)
        return LensDistortion(isEnabled: entry.enabled, strength: v[0], zoomToFill: v[1] >= 0.5)
    }

    static func writeLensDistortion(_ lens: LensDistortion, into entry: inout SceneEffectEntry) {
        entry.enabled = lens.isEnabled
        entry.parameters["strength"] = .double(lens.strength)
        entry.parameters["zoomToFill"] = .double(lens.zoomToFill ? 1 : 0)
    }
}
