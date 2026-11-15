// SceneEffectChain.swift — FX-020 effect chains in the scene document (FX-020-R4 to R7; research FX-020-D4 to D6;
// specs/142-fx-020-effect-chains/contracts/effect-chain.md E2; ADR-0054).
//
// An optional top-level `effects` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is `{"kind", "enabled", "parameters"}` plus any
// unknown fields, kept verbatim. The first entry of each reorderable kind (`fx.trails`, `fx.grade`, FX-006's
// `fx.chromatic`, FX-008's `fx.radialBlur`, FX-012's `fx.mosaic`, FX-014's `fx.edgeOutline`, FX-016's `fx.lensDistortion`) gives that effect's
// position, flag and parameters; repeated kinds, fixed stages (`fx.flashGuard`, `fx.toneMap`) and unknown kinds are kept
// at their index, never rendered, and reported as warnings. Plain Swift, no Foundation.
// FX-005 (specs/292-fx-005-contrast-curves, research FX-005-D8): the `fx.grade` entry may carry `contrast` (a preset
// name) and `contrastStrength` (0…1). Missing → Linear and 0.5; an unknown or non-string name → Linear with a warning.
// They are written only when the curve is not Linear or the stored entry already had them, so other scenes are unchanged.
// FX-013 (specs/301-fx-013-posterization, research FX-013-D8): `posterize` (bool), `posterizeLevels` (2…32, rounded) and
// `posterizeDither` (bool). Missing → off, 6, off; a malformed value → its default with a warning. Written only while
// posterize is on or when the stored entry already had any of them.
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
    /// FX-006 (ADR-0104): `isEnabled` is the entry's flag.
    public var chromatic: ChromaticSplit?
    /// FX-007 (ADR-0106): `isEnabled` is the entry's flag.
    public var directionalBlur: DirectionalBlur?
    /// FX-008 (ADR-0107): `isEnabled` is the entry's flag.
    public var radialBlur: RadialBlur?
    /// FX-010 (ADR-0108): `isEnabled` is the entry's flag; the weight cap is not stored (ACC-012 sets it live).
    public var echo: EchoFeedback?
    /// FX-012 (ADR-0110): `isEnabled` is the entry's flag (`SceneEffectChain+Mosaic.swift`).
    public var mosaic: Mosaic?
    /// FX-014 (ADR-0114): `isEnabled` is the entry's flag (`SceneEffectChain+EdgeOutline.swift`).
    public var edgeOutline: EdgeOutline?
    /// FX-016 (ADR-0117): `isEnabled` is the entry's flag (`SceneEffectChain+LensDistortion.swift`); set after `init`.
    public var lensDistortion: LensDistortion?

    public init(order: OutputEffectOrder = .standard, grade: ColorGrade? = nil, gradeEnabled: Bool? = nil, trails: MotionFeedback? = nil,
                chromatic: ChromaticSplit? = nil, directionalBlur: DirectionalBlur? = nil, radialBlur: RadialBlur? = nil,
                echo: EchoFeedback? = nil, mosaic: Mosaic? = nil, edgeOutline: EdgeOutline? = nil) {
        self.order = order
        self.grade = grade
        self.gradeEnabled = gradeEnabled
        self.trails = trails
        self.chromatic = chromatic
        self.directionalBlur = directionalBlur
        self.radialBlur = radialBlur
        self.echo = echo
        self.mosaic = mosaic   // FX-012
        self.edgeOutline = edgeOutline   // FX-014
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
    /// FX-006: `radial` is 0 or 1 (≥ 0.5 reads as on).
    static let chromaticParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "amount", range: ChromaticSplit.amountRange, fallback: ChromaticSplit.defaultAmount),
        SceneEffectParameter(name: "angle", range: ChromaticSplit.angleRange, fallback: ChromaticSplit.defaultAngle),
        SceneEffectParameter(name: "radial", range: 0...1, fallback: 0),
    ]
    /// FX-007: `radius` is a fraction of the shorter side, `angle` the blur axis in degrees.
    static let directionalBlurParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "radius", range: DirectionalBlur.radiusRange, fallback: DirectionalBlur.defaultRadius),
        SceneEffectParameter(name: "angle", range: DirectionalBlur.angleRange, fallback: DirectionalBlur.defaultAngle),
    ]
    /// FX-008: strength and the focus (fractions of the frame).
    static let radialBlurParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "strength", range: RadialBlur.strengthRange, fallback: RadialBlur.defaultStrength),
        SceneEffectParameter(name: "focusX", range: RadialBlur.focusRange, fallback: RadialBlur.defaultFocus),
        SceneEffectParameter(name: "focusY", range: RadialBlur.focusRange, fallback: RadialBlur.defaultFocus),
    ]
    /// FX-010: `count` echoes (0…4, rounded; above 4 is clamped and reported), `delay` in seconds, `decay` per echo.
    static let echoParameters: [SceneEffectParameter] = [
        SceneEffectParameter(name: "count", range: 0...Double(EchoFeedback.cap), fallback: Double(EchoFeedback.defaultCount)),
        SceneEffectParameter(name: "delay", range: EchoFeedback.delayRange, fallback: EchoFeedback.defaultDelay),
        SceneEffectParameter(name: "decay", range: EchoFeedback.decayRange, fallback: EchoFeedback.defaultDecay),
    ]

    /// Standard order, Trails off (or absent), Color on and neutral (or absent): nothing to save (research FX-020-D7).
    public var isDefault: Bool {
        let trailsOff: Bool = !(trails?.isEnabled ?? false)
        let gradeNeutral: Bool = grade?.isNeutral ?? true
        let chromaticOff: Bool = !(chromatic?.isEnabled ?? false)   // FX-006
        let blurOff: Bool = !(directionalBlur?.isEnabled ?? false)   // FX-007
        let radialBlurOff: Bool = !(radialBlur?.isEnabled ?? false)   // FX-008
        let echoOff: Bool = !(echo?.isEnabled ?? false)   // FX-010
        let mosaicOff: Bool = !(mosaic?.isEnabled ?? false)   // FX-012
        let outlineOff: Bool = !(edgeOutline?.isEnabled ?? false)   // FX-014
        let lensOff: Bool = !(lensDistortion?.isEnabled ?? false)   // FX-016
        return order == .standard && trailsOff && (gradeEnabled ?? true) && gradeNeutral && chromaticOff && blurOff && radialBlurOff
            && echoOff && mosaicOff && outlineOff && lensOff
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
                    var g = ColorGrade(temperature: v[0], lift: v[1], gamma: v[2], gain: v[3], saturation: v[4], hue: v[5])
                    readContrast(entry, path, &issues, into: &g)   // FX-005
                    readPosterize(entry, path, &issues, into: &g)   // FX-013
                    settings.grade = g
                    settings.gradeEnabled = entry.enabled
                case .trails:
                    let v = values(entry, trailsParameters, path, &issues)
                    settings.trails = MotionFeedback(isEnabled: entry.enabled, halfLifeSeconds: v[0])
                case .chromatic:   // FX-006
                    let v = values(entry, chromaticParameters, path, &issues)
                    settings.chromatic = ChromaticSplit(isEnabled: entry.enabled, amount: v[0], angleDegrees: v[1], isRadial: v[2] >= 0.5)
                case .directionalBlur:   // FX-007
                    let v = values(entry, directionalBlurParameters, path, &issues)
                    settings.directionalBlur = DirectionalBlur(isEnabled: entry.enabled, radius: v[0], angleDegrees: v[1])
                case .radialBlur:   // FX-008
                    let v = values(entry, radialBlurParameters, path, &issues)
                    settings.radialBlur = RadialBlur(isEnabled: entry.enabled, strength: v[0], focusX: v[1], focusY: v[2])
                case .echo:   // FX-010
                    let v = values(entry, echoParameters, path, &issues)
                    settings.echo = EchoFeedback(isEnabled: entry.enabled, count: EchoFeedback.clampCount(v[0]),
                                                 delaySeconds: v[1], decay: v[2])
                case .mosaic:   // FX-012
                    settings.mosaic = readMosaic(entry, path, &issues)
                case .edgeOutline:   // FX-014
                    settings.edgeOutline = readEdgeOutline(entry, path, &issues)
                case .lensDistortion:   // FX-016
                    settings.lensDistortion = readLensDistortion(entry, path, &issues)
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
    static func values(_ entry: SceneEffectEntry, _ table: [SceneEffectParameter], _ path: String,
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
            Self.writeContrast(g, into: &entry)   // FX-005
            Self.writePosterize(g, into: &entry)   // FX-013
        case .trails:
            guard let t = trails else { return stored }
            entry.enabled = t.isEnabled
            entry.parameters["halfLife"] = .double(t.halfLifeSeconds)
        case .chromatic:   // FX-006
            guard let c = chromatic else { return stored }
            entry.enabled = c.isEnabled
            entry.parameters["amount"] = .double(c.amount)
            entry.parameters["angle"] = .double(c.angleDegrees)
            entry.parameters["radial"] = .double(c.isRadial ? 1 : 0)
        case .directionalBlur:   // FX-007
            guard let b = directionalBlur else { return stored }
            entry.enabled = b.isEnabled
            entry.parameters["radius"] = .double(b.radius)
            entry.parameters["angle"] = .double(b.angleDegrees)
        case .radialBlur:   // FX-008
            guard let r = radialBlur else { return stored }
            entry.enabled = r.isEnabled
            entry.parameters["strength"] = .double(r.strength)
            entry.parameters["focusX"] = .double(r.focusX)
            entry.parameters["focusY"] = .double(r.focusY)
        case .echo:   // FX-010
            guard let e = echo else { return stored }
            entry.enabled = e.isEnabled
            entry.parameters["count"] = .double(Double(e.count))
            entry.parameters["delay"] = .double(e.delaySeconds)
            entry.parameters["decay"] = .double(e.decay)
        case .mosaic:   // FX-012
            guard let m = mosaic else { return stored }
            Self.writeMosaic(m, into: &entry)
        case .edgeOutline:   // FX-014
            guard let o = edgeOutline else { return stored }
            Self.writeEdgeOutline(o, into: &entry)
        case .lensDistortion:   // FX-016
            guard let l = lensDistortion else { return stored }
            Self.writeLensDistortion(l, into: &entry)
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

// MARK: - FX-005 contrast curve in the grade entry

extension SceneEffectSettings {
    static let contrastKey = "contrast"
    static let contrastStrengthParameter = SceneEffectParameter(name: "contrastStrength", range: ContrastCurve.strengthRange,
                                                                fallback: ContrastCurve.defaultStrength)

    /// Reads `contrast` and `contrastStrength` (research FX-005-D8).
    static func readContrast(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue], into grade: inout ColorGrade) {
        grade.contrastStrength = values(entry, [contrastStrengthParameter], path, &issues)[0]
        guard let raw = entry.parameters[contrastKey] else { return }
        let location: String = path + ".parameters." + contrastKey
        guard let name = raw.stringValue, let curve = ContrastCurve(rawValue: name) else {
            issues.append(SceneIssue(.valueClamped, path: location, "\(location) is not a known contrast curve; read as linear."))
            return
        }
        grade.contrast = curve
    }

    /// Writes both fields when the curve is not Linear or the entry already had them (an unknown stored name that the
    /// live grade still reads as Linear is left as written).
    static func writeContrast(_ grade: ColorGrade, into entry: inout SceneEffectEntry) {
        let had: Bool = entry.parameters[contrastKey] != nil || entry.parameters[contrastStrengthParameter.name] != nil
        guard had || grade.contrast != .linear else { return }
        if grade.contrast == .linear, let raw = entry.parameters[contrastKey],
           ContrastCurve(rawValue: raw.stringValue ?? "") == nil { return }   // an unknown name read as Linear is kept
        entry.parameters[contrastKey] = .string(grade.contrast.rawValue)
        entry.parameters[contrastStrengthParameter.name] = .double(grade.contrastStrength)
    }
}

// MARK: - FX-013 posterize in the grade entry

extension SceneEffectSettings {
    static let posterizeKey = "posterize"
    static let posterizeDitherKey = "posterizeDither"
    static let posterizeLevelsParameter = SceneEffectParameter(
        name: "posterizeLevels",
        range: Double(Posterize.levelsRange.lowerBound)...Double(Posterize.levelsRange.upperBound),
        fallback: Double(Posterize.defaultLevels))

    /// Reads `posterize`, `posterizeLevels` and `posterizeDither` (research FX-013-D8).
    static func readPosterize(_ entry: SceneEffectEntry, _ path: String, _ issues: inout [SceneIssue], into grade: inout ColorGrade) {
        let levels: Double = values(entry, [posterizeLevelsParameter], path, &issues)[0]
        grade.posterizeLevels = Posterize.levels(from: levels)
        grade.posterize = flag(entry, posterizeKey, path, &issues)
        grade.posterizeDither = flag(entry, posterizeDitherKey, path, &issues)
    }

    /// A Bool parameter: missing → off; not a Bool → off with a warning.
    private static func flag(_ entry: SceneEffectEntry, _ key: String, _ path: String, _ issues: inout [SceneIssue]) -> Bool {
        guard let raw = entry.parameters[key] else { return false }
        guard let value = raw.boolValue else {
            let location: String = path + ".parameters." + key
            issues.append(SceneIssue(.valueClamped, path: location, "\(location) is not true or false; read as false."))
            return false
        }
        return value
    }

    /// Writes the three fields while posterize is on or when the entry already had any of them.
    static func writePosterize(_ grade: ColorGrade, into entry: inout SceneEffectEntry) {
        let names: [String] = [posterizeKey, posterizeLevelsParameter.name, posterizeDitherKey]
        let had: Bool = names.contains { (name: String) -> Bool in entry.parameters[name] != nil }
        guard had || grade.posterize else { return }
        entry.parameters[posterizeKey] = .bool(grade.posterize)
        entry.parameters[posterizeLevelsParameter.name] = .double(Double(Posterize.clampLevels(grade.posterizeLevels)))
        entry.parameters[posterizeDitherKey] = .bool(grade.posterizeDither)
    }
}
