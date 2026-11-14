// SceneEffectChain.swift — FX-020 effect chains in the scene document (FX-020-R4 to R7; research FX-020-D4 to D6;
// specs/142-fx-020-effect-chains/contracts/effect-chain.md E2; ADR-0054).
//
// An optional top-level `effects` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is `{"kind", "enabled", "parameters"}` plus any
// unknown fields, kept verbatim. The first entry of each reorderable kind (`fx.trails`, `fx.grade`) gives that effect's
// position, flag and parameters; repeated kinds, fixed stages (`fx.flashGuard`, `fx.toneMap`) and unknown kinds are kept
// at their index, never rendered, and reported as warnings. Plain Swift, no Foundation.
import Compositor

/// One saved effect.
public struct SceneEffectEntry: Sendable, Hashable {
    public var kind: String
    public var enabled: Bool
    /// As written (known names are read as numbers; anything else is kept).
    public var parameters: [String: SceneJSON]
    /// Unknown entry fields, kept verbatim.
    public var extra: [String: SceneJSON]

    public init(kind: String, enabled: Bool = true, parameters: [String: SceneJSON] = [:], extra: [String: SceneJSON] = [:]) {
        self.kind = kind
        self.enabled = enabled
        self.parameters = parameters
        self.extra = extra
    }

    var json: SceneJSON {
        var o = extra
        o["kind"] = .string(kind)
        o["enabled"] = .bool(enabled)
        o["parameters"] = .object(parameters)
        return .object(o)
    }

    /// Reads one entry: `kind` a string (required), `enabled` a boolean, `parameters` an object (both optional).
    static func decode(_ value: SceneJSON, path: String) throws(SceneDecodeError) -> SceneEffectEntry {
        guard let o = value.objectValue else { throw .malformed(path: path, reason: "expected an object, found \(value.typeName)") }
        guard let kindValue = o["kind"] else { throw .malformed(path: path, reason: "\"kind\" is required") }
        guard let kind = kindValue.stringValue else {
            throw .malformed(path: ScenePath.key(path, "kind"), reason: "expected a string, found \(kindValue.typeName)")
        }
        var enabled = true
        if let e = o["enabled"] {
            guard let b = e.boolValue else { throw .malformed(path: ScenePath.key(path, "enabled"), reason: "expected a boolean, found \(e.typeName)") }
            enabled = b
        }
        var parameters: [String: SceneJSON] = [:]
        if let p = o["parameters"] {
            guard let object = p.objectValue else {
                throw .malformed(path: ScenePath.key(path, "parameters"), reason: "expected an object, found \(p.typeName)")
            }
            parameters = object
        }
        let known: Set<String> = ["kind", "enabled", "parameters"]
        return SceneEffectEntry(kind: kind, enabled: enabled, parameters: parameters,
                                extra: o.filter { (key: String, _: SceneJSON) -> Bool in !known.contains(key) })
    }
}

extension SceneLimits {
    /// FX-020: entries in `effects` (FX-001's chain limit).
    public static let maximumEffects = 16
}

/// One known parameter of a reorderable effect.
struct SceneEffectParameter {
    let name: String
    let range: ClosedRange<Double>
    let fallback: Double
}

/// The live values a chain gives (nil: the chain has no entry for that effect, so its current values stay).
public struct SceneEffectSettings: Sendable, Equatable {
    public var order: OutputEffectOrder
    public var grade: ColorGrade?
    public var gradeEnabled: Bool?
    /// `isEnabled` is the entry's flag.
    public var trails: MotionFeedback?

    public init(order: OutputEffectOrder = .standard, grade: ColorGrade? = nil, gradeEnabled: Bool? = nil, trails: MotionFeedback? = nil) {
        self.order = order
        self.grade = grade
        self.gradeEnabled = gradeEnabled
        self.trails = trails
    }

    static let gradeParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "temperature", range: ColorGrade.temperatureRange, fallback: 0),
        SceneEffectParameter(name: "lift", range: ColorGrade.liftRange, fallback: 0),
        SceneEffectParameter(name: "gamma", range: ColorGrade.gammaRange, fallback: 1),
        SceneEffectParameter(name: "gain", range: ColorGrade.gainRange, fallback: 1),
        SceneEffectParameter(name: "saturation", range: ColorGrade.saturationRange, fallback: 1),
        SceneEffectParameter(name: "hue", range: ColorGrade.hueRange, fallback: 0),
    ]
    static let trailsParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "halfLife", range: MotionFeedback.halfLifeRange, fallback: MotionFeedback.defaultHalfLife),
    ]

    /// Standard order, Trails off (or absent), Color on and neutral (or absent): nothing to save (research FX-020-D7).
    public var isDefault: Bool {
        let trailsOff: Bool = !(trails?.isEnabled ?? false)
        let gradeNeutral: Bool = grade?.isNeutral ?? true
        return order == .standard && trailsOff && (gradeEnabled ?? true) && gradeNeutral
    }

    // MARK: Reading

    /// The live values of `entries` and the warnings they give (research FX-020-D5).
    public static func read(_ entries: [SceneEffectEntry]) -> (settings: SceneEffectSettings, issues: [SceneIssue]) {
        var settings = SceneEffectSettings()
        var issues: [SceneIssue] = []
        var listed: [OutputEffectKind] = []
        for (i, entry) in entries.enumerated() {
            let path = "$.effects[\(i)]"
            if let kind = OutputEffectKind(rawValue: entry.kind) {
                if listed.contains(kind) {
                    issues.append(SceneIssue(.duplicateEffect, path: path + ".kind",
                                             "Effect \(i + 1) repeats \"\(entry.kind)\"; only the first is used. It is kept in the scene."))
                    continue
                }
                listed.append(kind)
                switch kind {
                case .grade:
                    let v = values(entry, gradeParameters, path, &issues)
                    settings.grade = ColorGrade(temperature: v[0], lift: v[1], gamma: v[2], gain: v[3], saturation: v[4], hue: v[5])
                    settings.gradeEnabled = entry.enabled
                case .trails:
                    let v = values(entry, trailsParameters, path, &issues)
                    settings.trails = MotionFeedback(isEnabled: entry.enabled, halfLifeSeconds: v[0])
                }
            } else if FixedOutputStage(rawValue: entry.kind) != nil {
                issues.append(SceneIssue(.fixedEffectStage, path: path + ".kind",
                                         "Effect \(i + 1) is \"\(entry.kind)\"; flash safety and the tone map always run last. It is kept but has no effect."))
            } else {
                issues.append(SceneIssue(.unknownEffectKind, path: path + ".kind",
                                         "Effect \(i + 1) has the unknown kind \"\(entry.kind)\"; it is kept but not shown."))
            }
        }
        settings.order = OutputEffectOrder(listed)
        return (settings, issues)
    }

    /// The known parameters in table order: missing → fallback; not a finite number → fallback, out of range → clamped
    /// (both reported as `valueClamped`).
    private static func values(_ entry: SceneEffectEntry, _ table: [SceneEffectParameter], _ path: String,
                               _ issues: inout [SceneIssue]) -> [Double] {
        table.map { (p: SceneEffectParameter) -> Double in
            guard let raw = entry.parameters[p.name] else { return p.fallback }
            let location: String = path + ".parameters." + p.name
            guard let d = raw.numberValue?.doubleValue, d.isFinite else {
                issues.append(SceneIssue(.valueClamped, path: location, "\(location) is not a number; read as \(p.fallback)."))
                return p.fallback
            }
            let clamped: Double = min(max(d, p.range.lowerBound), p.range.upperBound)
            if clamped != d {
                issues.append(SceneIssue(.valueClamped, path: location, "\(location): \(d) is outside \(p.range); read as \(clamped)."))
            }
            return clamped
        }
    }

    // MARK: Writing

    /// The list to save (research FX-020-D6): the slots of `stored`'s first entry of each known kind are filled with the
    /// live entries in live order, every other entry keeps its index, live entries without a slot are appended. A kind
    /// without live values keeps its stored entry (or is left out).
    public func entries(over stored: [SceneEffectEntry]?) -> [SceneEffectEntry] {
        let saved: [SceneEffectEntry] = stored ?? []
        var firstIndex: [OutputEffectKind: Int] = [:]
        for (i, entry) in saved.enumerated() {
            if let kind = OutputEffectKind(rawValue: entry.kind), firstIndex[kind] == nil { firstIndex[kind] = i }
        }
        var live: [SceneEffectEntry] = order.effects.compactMap { (kind: OutputEffectKind) -> SceneEffectEntry? in
            liveEntry(kind, over: firstIndex[kind].map { (i: Int) -> SceneEffectEntry in saved[i] })
        }
        var result: [SceneEffectEntry] = []
        let slots = Set(firstIndex.values)
        for (i, entry) in saved.enumerated() {
            if slots.contains(i) {
                if !live.isEmpty { result.append(live.removeFirst()) }
            } else {
                result.append(entry)
            }
        }
        return result + live
    }

    private func liveEntry(_ kind: OutputEffectKind, over stored: SceneEffectEntry?) -> SceneEffectEntry? {
        var entry: SceneEffectEntry = stored ?? SceneEffectEntry(kind: kind.rawValue)
        switch kind {
        case .grade:
            guard let g = grade else { return stored }
            entry.enabled = gradeEnabled ?? true
            let values: [Double] = [g.temperature, g.lift, g.gamma, g.gain, g.saturation, g.hue]
            for (p, v) in zip(Self.gradeParameters, values) { entry.parameters[p.name] = .double(v) }
        case .trails:
            guard let t = trails else { return stored }
            entry.enabled = t.isEnabled
            entry.parameters["halfLife"] = .double(t.halfLifeSeconds)
        }
        return entry
    }
}

extension SceneDocument {
    /// FX-020: the live values of `effects` (nil when the scene has no list: the standard order, values untouched).
    public var effectSettings: SceneEffectSettings? {
        effects.map { (list: [SceneEffectEntry]) -> SceneEffectSettings in SceneEffectSettings.read(list).settings }
    }

    func effectIssues() -> [SceneIssue] {
        guard let effects else { return [] }
        return SceneEffectSettings.read(effects).issues
    }
}
