// SceneMacros.swift — MOD-010 parameter macros in the scene document (MOD-010-R7, R8; research MOD-010-D3;
// specs/170-mod-010-parameter-macro/contracts/parameter-macro.md M3).
//
// An optional top-level `macros` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is an object kept verbatim:
// `{"name": "Glow sweep", "value": 0.5, "targets": [{"parameter": "effect.bloom.intensity", "curve": "easeIn:2.0",
// "minimum": 0, "maximum": 1, "invert": false}]}` (`curve`, `minimum`, `maximum`, `invert` optional). `read` keeps
// positions: an unusable entry is nil, a macro keeps only its usable targets, and every problem is a warning at its
// path (`invalidMacro`, `unknownMacroTarget`); the entry stays in the document for re-save. Plain Swift, no Foundation.
import ParameterGraph

/// One stored macro, as written.
public struct SceneMacroEntry: Sendable, Hashable {
    /// Every field of the entry object, known and unknown, verbatim.
    public var fields: [String: SceneJSON]

    public init(fields: [String: SceneJSON]) {
        self.fields = fields
    }

    /// The entry for a macro (numbers written as given; `minimum`/`maximum` only when set).
    public init(_ macro: ParameterMacro) {
        let targets: [SceneJSON] = macro.targets.map { (t: MacroTarget) -> SceneJSON in
            var o: [String: SceneJSON] = ["parameter": .string(t.parameter.rawValue), "curve": .string(t.curve.textForm),
                                          "invert": .bool(t.inverted)]
            if let low = t.outputMinimum { o["minimum"] = .double(low) }
            if let high = t.outputMaximum { o["maximum"] = .double(high) }
            return .object(o)
        }
        fields = ["name": .string(macro.name), "value": .double(macro.value), "targets": .array(targets)]
    }

    /// The same entry with only its `value` replaced (unknown fields kept).
    public func settingValue(_ value: Double) -> SceneMacroEntry {
        var copy = self
        copy.fields["value"] = .double(value)
        return copy
    }

    var json: SceneJSON { .object(fields) }

    static func decode(_ value: SceneJSON, path: String) throws(SceneDecodeError) -> SceneMacroEntry {
        guard let o = value.objectValue else { throw .malformed(path: path, reason: "expected an object, found \(value.typeName)") }
        return SceneMacroEntry(fields: o)
    }

    /// The live macros of `entries` by position (nil for an unusable entry; at most `SceneLimits.maximumMacros`
    /// positions), each with its usable targets only, and the warnings, in order (contract M3).
    public static func read(_ entries: [SceneMacroEntry], registry: ParameterRegistry) -> (macros: [ParameterMacro?], issues: [SceneIssue]) {
        var macros: [ParameterMacro?] = []
        var issues: [SceneIssue] = []
        for (i, entry) in entries.enumerated() {
            let path = "$.macros[\(i)]"
            guard i < SceneLimits.maximumMacros else {
                issues.append(SceneIssue(.invalidMacro, path: path,
                                         "Macro \(i + 1) is beyond the limit of \(SceneLimits.maximumMacros); it is kept but not used."))
                continue
            }
            let read: (macro: ParameterMacro?, issues: [SceneIssue]) = entry.macro(at: path, number: i + 1, registry: registry)
            issues += read.issues
            macros.append(read.macro)
        }
        return (macros, issues)
    }

    private func macro(at path: String, number: Int, registry: ParameterRegistry) -> (macro: ParameterMacro?, issues: [SceneIssue]) {
        func invalid(_ key: String, _ what: String) -> (macro: ParameterMacro?, issues: [SceneIssue]) {
            (nil, [SceneIssue(.invalidMacro, path: ScenePath.key(path, key), "Macro \(number): \"\(key)\" \(what); it is kept but not used.")])
        }
        guard let name = fields["name"]?.stringValue, !name.isEmpty else { return invalid("name", "must be a non-empty string") }
        guard let value = fields["value"]?.numberValue?.doubleValue, value.isFinite else { return invalid("value", "must be a finite number") }
        guard let list = fields["targets"]?.arrayValue else { return invalid("targets", "must be a list") }
        guard list.count <= SceneLimits.maximumMacroTargetEntries else {
            return invalid("targets", "has more than \(SceneLimits.maximumMacroTargetEntries) entries")
        }
        var targets: [MacroTarget] = []
        var issues: [SceneIssue] = []
        var seen: Set<ParameterID> = []
        for (j, item) in list.enumerated() {
            let targetPath = ScenePath.index(ScenePath.key(path, "targets"), j)
            let label = "Macro \(number), target \(j + 1)"
            guard j < ParameterMacro.maximumTargets else {
                issues.append(SceneIssue(.invalidMacro, path: targetPath,
                                         "\(label) is beyond the limit of \(ParameterMacro.maximumTargets); it is kept but not used."))
                continue
            }
            let parsed: (target: MacroTarget?, issue: SceneIssue?) = Self.target(item, path: targetPath, label: label)
            guard let target = parsed.target else {
                if let issue = parsed.issue { issues.append(issue) }
                continue
            }
            if let issue = Self.problemIssue(target, seen: seen, path: targetPath, label: label, registry: registry) {
                issues.append(issue)
                continue
            }
            seen.insert(target.parameter)
            targets.append(target)
        }
        return (ParameterMacro(name: name, value: value, targets: targets), issues)
    }

    private static func target(_ item: SceneJSON, path: String, label: String) -> (target: MacroTarget?, issue: SceneIssue?) {
        func invalid(_ key: String?, _ what: String) -> (target: MacroTarget?, issue: SceneIssue?) {
            let at: String = key.map { (k: String) -> String in ScenePath.key(path, k) } ?? path
            let subject: String = key.map { (k: String) -> String in "\"\(k)\" " } ?? ""
            return (nil, SceneIssue(.invalidMacro, path: at, "\(label): \(subject)\(what); it is kept but not used."))
        }
        guard let o = item.objectValue else { return invalid(nil, "must be an object") }
        guard let raw = o["parameter"]?.stringValue else { return invalid("parameter", "must be a parameter ID") }
        var curve: MappingCurve = .linear
        if let value = o["curve"] {
            guard let text = value.stringValue, let parsed = MappingCurve(textForm: text) else { return invalid("curve", "must be a curve") }
            curve = parsed
        }
        var bounds: [Double?] = []
        for key in ["minimum", "maximum"] {
            guard let value = o[key] else {
                bounds.append(nil)
                continue
            }
            guard let d = value.numberValue?.doubleValue, d.isFinite else { return invalid(key, "must be a finite number") }
            bounds.append(d)
        }
        var inverted = false
        if let value = o["invert"] {
            guard let b = value.boolValue else { return invalid("invert", "must be true or false") }
            inverted = b
        }
        let target = MacroTarget(parameter: ParameterID(raw), curve: curve, outputMinimum: bounds[0], outputMaximum: bounds[1],
                                 inverted: inverted)
        return (target, nil)
    }

    private static func problemIssue(_ target: MacroTarget, seen: Set<ParameterID>, path: String, label: String,
                                     registry: ParameterRegistry) -> SceneIssue? {
        let descriptor: ParameterDescriptor? = registry.descriptor(for: target.parameter)
        if let problem = target.problem(descriptor: descriptor) {
            if problem == .unknownParameter {
                return SceneIssue(.unknownMacroTarget, path: ScenePath.key(path, "parameter"),
                                  "\(label) drives \"\(target.parameter.rawValue)\", unknown to this version; it is kept but not used.")
            }
            return SceneIssue(.invalidMacro, path: path, "\(label): \(problem); it is kept but not used.")
        }
        if seen.contains(target.parameter) {
            return SceneIssue(.invalidMacro, path: path, "\(label): \(MacroProblem.duplicateParameter); it is kept but not used.")
        }
        return nil
    }
}

extension SceneLimits {
    /// MOD-010: live macros per scene (`ParameterMacro.maximumMacros`); more entries are kept, not used.
    public static let maximumMacros = ParameterMacro.maximumMacros
    /// MOD-010: entries in `macros` the decoder accepts at all.
    public static let maximumMacroEntries = 64
    /// MOD-010: targets one stored macro may list (the first `ParameterMacro.maximumTargets` are used).
    public static let maximumMacroTargetEntries = 64
}

extension SceneDocument {
    /// MOD-010: the live macros of the document by position (empty without a `macros` list).
    public func liveMacros(registry: ParameterRegistry) -> [ParameterMacro?] {
        SceneMacroEntry.read(macros ?? [], registry: registry).macros
    }
}
