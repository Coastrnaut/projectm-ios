// SceneTriggers.swift — MOD-006 threshold triggers in the scene document (MOD-006-R9, R10; research MOD-006-D6, D7;
// specs/148-mod-006-threshold-trigger/contracts/threshold-trigger.md T4, T5).
//
// An optional top-level `triggers` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is an object kept verbatim:
// `{"source": "audio.kick", "action": "cue.next", "high": 0.6, "low": 0.3, "minimumInterval": 0.1, "hold": 0}`
// (`minimumInterval` and `hold` optional). `read` turns the entries into live bindings; an entry that cannot be used
// is reported with a warning at its path and stays in the document for re-save, so one trigger never refuses a scene.
// Plain Swift, no Foundation.
import ParameterGraph

/// One stored threshold trigger, as written.
public struct SceneTriggerEntry: Sendable, Hashable {
    /// Every field of the entry object, known and unknown, verbatim.
    public var fields: [String: SceneJSON]

    public init(fields: [String: SceneJSON]) {
        self.fields = fields
    }

    /// The entry for a live binding (numbers written as given).
    public init(_ binding: ThresholdTriggerBinding) {
        fields = [
            "source": .string(binding.source.id),
            "action": .string(binding.action.rawValue),
            "high": .double(binding.settings.high),
            "low": .double(binding.settings.low),
            "minimumInterval": .double(binding.settings.minimumIntervalSeconds),
            "hold": .double(binding.settings.holdSeconds),
        ]
    }

    var json: SceneJSON { .object(fields) }

    static func decode(_ value: SceneJSON, path: String) throws(SceneDecodeError) -> SceneTriggerEntry {
        guard let o = value.objectValue else { throw .malformed(path: path, reason: "expected an object, found \(value.typeName)") }
        return SceneTriggerEntry(fields: o)
    }

    /// The live bindings of `entries` and the warnings for the ones that cannot be used, in order (contract T5).
    public static func read(_ entries: [SceneTriggerEntry]) -> (bindings: [ThresholdTriggerBinding], issues: [SceneIssue]) {
        var bindings: [ThresholdTriggerBinding] = []
        var issues: [SceneIssue] = []
        for (i, entry) in entries.enumerated() {
            let read: (binding: ThresholdTriggerBinding?, issue: SceneIssue?) = entry.binding(at: "$.triggers[\(i)]", number: i + 1)
            if let issue = read.issue { issues.append(issue) }
            guard let binding = read.binding else { continue }
            if bindings.count < SceneLimits.maximumTriggers {
                bindings.append(binding)
            } else {
                issues.append(SceneIssue(.invalidTrigger, path: "$.triggers[\(i)]",
                                         "Trigger \(i + 1) is beyond the limit of \(SceneLimits.maximumTriggers); it is kept but not used."))
            }
        }
        return (bindings, issues)
    }

    private func binding(at path: String, number: Int) -> (binding: ThresholdTriggerBinding?, issue: SceneIssue?) {
        func invalid(_ key: String, _ what: String) -> (binding: ThresholdTriggerBinding?, issue: SceneIssue?) {
            (nil, SceneIssue(.invalidTrigger, path: ScenePath.key(path, key), "Trigger \(number): \"\(key)\" \(what); it is kept but not used."))
        }
        guard let sourceID = fields["source"]?.stringValue else { return invalid("source", "must be an audio feature ID") }
        guard let actionID = fields["action"]?.stringValue else { return invalid("action", "must be an action name") }
        var numbers: [Double] = []
        let keys: [(key: String, fallback: Double?)] = [("high", nil), ("low", nil),
                                                         ("minimumInterval", ThresholdTriggerSettings.defaultMinimumIntervalSeconds), ("hold", 0)]
        for entry in keys {
            guard let value = fields[entry.key] else {
                guard let fallback = entry.fallback else { return invalid(entry.key, "is required") }
                numbers.append(fallback)
                continue
            }
            guard let d = value.numberValue?.doubleValue, d.isFinite else { return invalid(entry.key, "must be a finite number") }
            numbers.append(d)
        }
        guard let source = AudioFeatureSource(id: sourceID) else {
            return (nil, SceneIssue(.unknownTrigger, path: ScenePath.key(path, "source"),
                                    "Trigger \(number) uses the audio feature \"\(sourceID)\", unknown to this version; it is kept but not used."))
        }
        guard let action = ThresholdTriggerAction(rawValue: actionID) else {
            return (nil, SceneIssue(.unknownTrigger, path: ScenePath.key(path, "action"),
                                    "Trigger \(number) uses the action \"\(actionID)\", unknown to this version; it is kept but not used."))
        }
        let settings = ThresholdTriggerSettings(high: numbers[0], low: numbers[1], minimumIntervalSeconds: numbers[2], holdSeconds: numbers[3])
        if let problem = settings.validationProblem {
            return (nil, SceneIssue(.invalidTrigger, path: path, "Trigger \(number): \(problem); it is kept but not used."))
        }
        return (ThresholdTriggerBinding(source: source, action: action, settings: settings), nil)
    }
}

extension SceneLimits {
    /// MOD-006: live triggers per scene (`ThresholdTriggerBank.maximumTriggers`); more entries are kept, not used.
    public static let maximumTriggers = ThresholdTriggerBank.maximumTriggers
    /// MOD-006: entries in `triggers` the decoder accepts at all.
    public static let maximumTriggerEntries = 64
}

extension SceneDocument {
    /// MOD-006: the live triggers of the document (empty without a `triggers` list).
    public var triggerBindings: [ThresholdTriggerBinding] { SceneTriggerEntry.read(triggers ?? []).bindings }
}
