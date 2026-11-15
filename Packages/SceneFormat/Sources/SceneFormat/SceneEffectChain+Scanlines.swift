// SceneEffectChain+Scanlines.swift — FX-018: the `fx.scanlines` entry of the FX-020 `effects` list
// (specs/312-fx-018-scanline-texture, contracts/scanlines.md C3, research FX-018-D7; ADR-0123).
//
// Parameters: `spacing` (whole pixels, 2…16; rounded), `thickness` (whole pixels, 1…15; rounded; drawn as at most
// spacing − 1), `intensity` (0…1) and `vertical` (0 or 1; ≥ 0.5 reads as vertical, like FX-012's `shape`). Missing →
// the default; not a number or out of range → default or nearest bound, reported. The entry is written only while the
// scanlines are on (disabled is default), so older scenes encode byte-identically.
import Compositor

extension SceneEffectSettings {
    static let scanlinesParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "spacing",
                             range: Double(Scanlines.spacingRange.lowerBound)...Double(Scanlines.spacingRange.upperBound),
                             fallback: Double(Scanlines.defaultSpacing)),
        SceneEffectParameter(name: "thickness",
                             range: Double(Scanlines.thicknessRange.lowerBound)...Double(Scanlines.thicknessRange.upperBound),
                             fallback: Double(Scanlines.defaultThickness)),
        SceneEffectParameter(name: "intensity", range: Scanlines.intensityRange, fallback: Scanlines.defaultIntensity),
        SceneEffectParameter(name: "vertical", range: 0...1, fallback: 0),
    ]

    static func readScanlines(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> Scanlines {
        let v: [Double] = values(entry, scanlinesParameters, path, &issues)
        return Scanlines(isEnabled: entry.enabled, spacing: Scanlines.clampSpacing(v[0]),
                         thickness: Scanlines.clampThickness(v[1]), intensity: v[2], isVertical: v[3] >= 0.5)
    }

    static func writeScanlines(_ scanlines: Scanlines, into entry: inout SceneEffectEntry) {
        entry.enabled = scanlines.isEnabled
        entry.parameters["spacing"] = .double(Double(scanlines.spacing))
        entry.parameters["thickness"] = .double(Double(scanlines.thickness))
        entry.parameters["intensity"] = .double(scanlines.intensity)
        entry.parameters["vertical"] = .double(scanlines.isVertical ? 1 : 0)
    }
}
