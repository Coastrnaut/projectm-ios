// SceneEffectChain+Mosaic.swift — FX-012: the `fx.mosaic` entry of the FX-020 `effects` list
// (specs/299-fx-012-mosaic-pixelation, contracts/mosaic.md C3, research FX-012-D6; ADR-0110).
//
// Parameters: `size` (whole pixels, 1…64; rounded) and `shape` (0 square, 1 hexagon; ≥ 0.5 reads as hexagon, like
// FX-006's `radial`). Missing → the default; not a number or out of range → default or nearest bound, reported. The
// entry is written only while the mosaic is on (a disabled mosaic is default), so older scenes encode byte-identically.
import Compositor

extension SceneEffectSettings {
    static let mosaicParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "size", range: Double(Mosaic.sizeRange.lowerBound)...Double(Mosaic.sizeRange.upperBound),
                             fallback: Double(Mosaic.defaultSize)),
        SceneEffectParameter(name: "shape", range: 0...1, fallback: 0),
    ]

    static func readMosaic(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> Mosaic {
        let v: [Double] = values(entry, mosaicParameters, path, &issues)
        let shape: MosaicShape = v[1] >= 0.5 ? .hexagon : .square
        return Mosaic(isEnabled: entry.enabled, blockSize: Mosaic.clampSize(v[0]), shape: shape)
    }

    static func writeMosaic(_ mosaic: Mosaic, into entry: inout SceneEffectEntry) {
        entry.enabled = mosaic.isEnabled
        entry.parameters["size"] = .double(Double(mosaic.blockSize))
        entry.parameters["shape"] = .double(mosaic.shape == .hexagon ? 1 : 0)
    }
}
