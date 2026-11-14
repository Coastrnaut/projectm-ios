// OutputEffectOrder.swift — FX-020: the order of the reorderable output effects (specs/142-fx-020-effect-chains,
// contracts/effect-chain.md E1, research FX-020-D1; ADR-0052). Plain Swift, builds on Linux.
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

    /// Today's order: Trails, then Color (FX-020-R1).
    public static let standard = OutputEffectOrder([.trails, .grade])

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

    /// `fx.trails,fx.grade` (the app's stored form).
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
