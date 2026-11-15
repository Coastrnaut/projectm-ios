// SceneEffectChain+EdgeOutline.swift — FX-014: the `fx.edgeOutline` entry of the FX-020 `effects` list
// (specs/303-fx-014-edge-outline, contracts/edge-outline.md C3, research FX-014-D7; ADR-0114).
//
// Parameters: `threshold` (0.02…1), `width` (whole pixels, 1…3; rounded), `red`, `green`, `blue` (sRGB 0…1) and `mode`
// (0 overlay, 1 outline only; ≥ 0.5 reads as outline only, like FX-006's `radial`). Missing → the default; not a number
// or out of range → default or nearest bound, reported. The entry is written only while the outline is on (a disabled
// outline is default), so older scenes encode byte-identically. The ACC-012 colour scale is never stored.
import Compositor

extension SceneEffectSettings {
    static let edgeOutlineParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "threshold", range: EdgeOutline.thresholdRange, fallback: EdgeOutline.defaultThreshold),
        SceneEffectParameter(name: "width", range: Double(EdgeOutline.widthRange.lowerBound)...Double(EdgeOutline.widthRange.upperBound),
                             fallback: Double(EdgeOutline.defaultWidth)),
        SceneEffectParameter(name: "red", range: 0...1, fallback: 1),
        SceneEffectParameter(name: "green", range: 0...1, fallback: 1),
        SceneEffectParameter(name: "blue", range: 0...1, fallback: 1),
        SceneEffectParameter(name: "mode", range: 0...1, fallback: 0),
    ]

    static func readEdgeOutline(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> EdgeOutline {
        let v: [Double] = values(entry, edgeOutlineParameters, path, &issues)
        let mode: EdgeOutlineMode = v[5] >= 0.5 ? .outlineOnly : .overlay
        return EdgeOutline(isEnabled: entry.enabled, threshold: EdgeOutline.clampThreshold(v[0]), width: EdgeOutline.clampWidth(v[1]),
                           color: EdgeOutlineColor(red: v[2], green: v[3], blue: v[4]), mode: mode)
    }

    static func writeEdgeOutline(_ outline: EdgeOutline, into entry: inout SceneEffectEntry) {
        entry.enabled = outline.isEnabled
        entry.parameters["threshold"] = .double(outline.threshold)
        entry.parameters["width"] = .double(Double(outline.width))
        entry.parameters["red"] = .double(outline.color.red)
        entry.parameters["green"] = .double(outline.color.green)
        entry.parameters["blue"] = .double(outline.color.blue)
        entry.parameters["mode"] = .double(outline.mode == .outlineOnly ? 1 : 0)
    }
}
