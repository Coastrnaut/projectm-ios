// SceneEffectChain+FilmGrain.swift — FX-017: the `fx.filmGrain` entry of the FX-020 `effects` list
// (specs/311-fx-017-film-grain, contracts/film-grain.md C3, research FX-017-D6; ADR-0122).
//
// Parameters: `opacity` (0…1), `size` (1…3, rounded), `color` (0…1, ≥ 0.5 colour), `seed` (0…9999, rounded) and
// `animated` (0…1, ≥ 0.5 on). Missing → the default; not a number or out of range → default or nearest bound, reported.
// The entry is written only while the grain is on (disabled grain is default), so older scenes encode byte-identically.
import Compositor

extension SceneEffectSettings {
    static let filmGrainParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "opacity", range: FilmGrain.opacityRange, fallback: FilmGrain.defaultOpacity),
        SceneEffectParameter(name: "size", range: 1...3, fallback: Double(FilmGrain.defaultSize)),
        SceneEffectParameter(name: "color", range: 0...1, fallback: 0),
        SceneEffectParameter(name: "seed", range: 0...9_999, fallback: Double(FilmGrain.defaultSeed)),
        SceneEffectParameter(name: "animated", range: 0...1, fallback: 0),
    ]

    static func readFilmGrain(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue]) -> FilmGrain {
        let v: [Double] = values(entry, filmGrainParameters, path, &issues)
        return FilmGrain(isEnabled: entry.enabled, opacity: v[0], size: FilmGrain.size(fromNumber: v[1]), isColor: v[2] >= 0.5,
                         seed: FilmGrain.seed(fromNumber: v[3]), isAnimated: v[4] >= 0.5)
    }

    static func writeFilmGrain(_ grain: FilmGrain, into entry: inout SceneEffectEntry) {
        entry.enabled = grain.isEnabled
        entry.parameters["opacity"] = .double(grain.opacity)
        entry.parameters["size"] = .double(Double(grain.size))
        entry.parameters["color"] = .double(grain.isColor ? 1 : 0)
        entry.parameters["seed"] = .double(Double(grain.seed))
        entry.parameters["animated"] = .double(grain.isAnimated ? 1 : 0)
    }
}
