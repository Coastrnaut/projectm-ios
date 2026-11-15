// SceneEffectChain+PixelSort.swift — FX-011: the `fx.pixelSort` entry of the FX-020 `effects` list
// (specs/310-fx-011-pixel-sorting, contracts/pixel-sort.md C4, research FX-011-D6; ADR-0121).
//
// Parameters: `threshold` (0…1), `span` (4…64, then rounded down to 4, 8, 16, 32 or 64) and `vertical` (0 or 1; ≥ 0.5
// reads as vertical, like FX-014's `mode`). Missing → the default; not a number or out of range → default or nearest
// bound, reported. The entry is written only while the sort is on (a disabled sort is default), so older scenes encode
// byte-identically.
import Compositor

extension SceneEffectSettings {
    static let pixelSortParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "threshold", range: PixelSort.thresholdRange, fallback: PixelSort.defaultThreshold),
        SceneEffectParameter(name: "span", range: Double(PixelSort.spans[0])...Double(PixelSort.maxSpan),
                             fallback: Double(PixelSort.defaultSpan)),
        SceneEffectParameter(name: "vertical", range: 0...1, fallback: 0),
    ]

    static func readPixelSort(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> PixelSort {
        let v: [Double] = values(entry, pixelSortParameters, path, &issues)
        return PixelSort(isEnabled: entry.enabled, threshold: v[0], span: PixelSort.snapSpan(v[1]),
                         direction: v[2] >= 0.5 ? .vertical : .horizontal)
    }

    static func writePixelSort(_ sort: PixelSort, into entry: inout SceneEffectEntry) {
        entry.enabled = sort.isEnabled
        entry.parameters["threshold"] = .double(sort.threshold)
        entry.parameters["span"] = .double(Double(sort.span))
        entry.parameters["vertical"] = .double(sort.direction == .vertical ? 1 : 0)
    }
}
