// OutputEffectOrder.swift — FX-020: the order of the reorderable output effects (specs/142-fx-020-effect-chains,
// contracts/effect-chain.md E1, research FX-020-D1; ADR-0054). Plain Swift, builds on Linux.
//
// Two effects act on the finished composite before safety and can be reordered: FX-009 Trails (`fx.trails`) and
// FX-003/FX-004 Color (`fx.grade`). The FX-019 flash guard and the FX-002 tone map are fixed stages that always run
// after them; they are named here only so documents that list them can be recognised (and never obeyed).

/// A reorderable output effect, by its stable stored kind.
public enum OutputEffectKind: String, CaseIterable, Sendable, Hashable {
    /// FX-009 Trails.
    case trails = "fx.trails"
    /// FX-003 colour grade with FX-004 hue.
    case grade = "fx.grade"
    /// FX-006 Chromatic split (appended: stored orders without it read with it last; ADR-0104).
    case chromatic = "fx.chromatic"
    /// FX-007 Directional blur (appended after the split: stored orders without it read with it last; ADR-0106).
    case directionalBlur = "fx.directionalBlur"
    /// FX-008 Radial blur (appended: stored orders without it read with it last; ADR-0107).
    case radialBlur = "fx.radialBlur"
    /// FX-010 Echo (appended last: stored orders without it read with it last; ADR-0108).
    case echo = "fx.echo"
    /// FX-012 Mosaic pixelation (appended after Echo: stored orders without it read with it last; ADR-0110).
    case mosaic = "fx.mosaic"
    /// FX-014 Edge outline (appended after Mosaic: stored orders without it read with it last; ADR-0114).
    case edgeOutline = "fx.edgeOutline"
    /// FX-016 Lens distortion (appended after Edge outline: stored orders without it read with it last; ADR-0117).
    case lensDistortion = "fx.lensDistortion"
    /// FX-015 Vignette (appended last, after Lens distortion: stored orders without it read with it last; ADR-0116).
    case vignette = "fx.vignette"
    /// FX-017 Film grain (appended last, after Vignette: stored orders without it read with it last; ADR-0122).
    case filmGrain = "fx.filmGrain"
}

/// A stage that always runs after every `OutputEffectKind` (FX-020-R2).
public enum FixedOutputStage: String, CaseIterable, Sendable, Hashable {
    /// FX-019 composite flash guard (with ACC-012's limits); its gain is applied last.
    case flashGuard = "fx.flashGuard"
    /// FX-002 output tone map.
    case toneMap = "fx.toneMap"
}

/// The order in which the reorderable output effects are applied: every kind exactly once.
public struct OutputEffectOrder: Sendable, Hashable, CustomStringConvertible {
    public let effects: [OutputEffectKind]

    /// Today's order: Trails, then Color (FX-020-R1), then FX-006's Chromatic split, FX-007's Directional blur,
    /// FX-008's Radial blur, FX-010's Echo and FX-012's Mosaic, then FX-014's Edge outline, FX-016's Lens distortion,
    /// FX-015's Vignette and FX-017's Film grain.
    public static let standard = OutputEffectOrder([.trails, .grade, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic,
                                                         .edgeOutline, .lensDistortion, .vignette, .filmGrain])   // FX-014, FX-016, FX-015, FX-017 appended

    /// Repeats are dropped (the first counts); missing kinds are appended in standard order.
    public init(_ kinds: [OutputEffectKind]) {
        var seen: Set<OutputEffectKind> = []
        var list: [OutputEffectKind] = []
        for kind in kinds where seen.insert(kind).inserted { list.append(kind) }
        for kind in OutputEffectKind.allCases where !seen.contains(kind) { list.append(kind) }
        effects = list
    }

    /// Color is applied before Trails.
    public var gradeBeforeTrails: Bool {
        let grade: Int = effects.firstIndex(of: .grade) ?? 0
        let trails: Int = effects.firstIndex(of: .trails) ?? 0
        return grade < trails
    }

    /// SwiftUI `move(fromOffsets:toOffset:)` semantics.
    public func moving(from source: [Int], to destination: Int) -> OutputEffectOrder {
        let picked: [OutputEffectKind] = source.sorted().compactMap { (i: Int) -> OutputEffectKind? in
            i >= 0 && i < effects.count ? effects[i] : nil
        }
        var rest: [OutputEffectKind] = []
        var insertAt: Int = 0
        for (i, kind) in effects.enumerated() where !source.contains(i) {
            if i < destination { insertAt += 1 }
            rest.append(kind)
        }
        rest.insert(contentsOf: picked, at: min(insertAt, rest.count))
        return OutputEffectOrder(rest)
    }

    /// `fx.trails,fx.grade,fx.chromatic,fx.directionalBlur,fx.radialBlur` (the app's stored form).
    public var storageText: String { effects.map(\.rawValue).joined(separator: ",") }

    /// Reads `storageText`; unknown tokens are ignored, so anything reads as a valid order.
    public init(storageText: String) {
        let kinds: [OutputEffectKind] = storageText.split(separator: ",").compactMap { (token: Substring) -> OutputEffectKind? in
            OutputEffectKind(rawValue: String(token))
        }
        self.init(kinds)
    }

    public var description: String { storageText }
}
