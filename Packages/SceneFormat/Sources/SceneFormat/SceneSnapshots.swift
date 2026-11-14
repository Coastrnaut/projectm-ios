// SceneSnapshots.swift — SCN-008 named parameter snapshots in the scene document (SCN-008-R1 to R7, R11;
// research SCN-008-D2 to D4, D9; specs/169-scn-008-scene-snapshots/contracts/scene-snapshots.md N1 to N7).
//
// An optional top-level `snapshots` array, written only when set (format version 1, so scenes without it encode
// byte-identically and QA-004's matrix gains no row). Each entry is an object kept verbatim:
// `{"name": "S1", "values": {"effect.bloom.intensity": {"kind": "continuous", "value": 0.2}}}`, values in the
// form of the document's `parameters`. `read` turns entries into snapshots by position; an entry that cannot be
// used is nil, reported with a warning at its path and stays in the document for re-save, so one snapshot never
// refuses a scene. `SceneSnapshotRecallPlan` checks a snapshot against the registry before the app writes it.
// Plain Swift, no Foundation.
import ParameterGraph

/// One stored snapshot, as written.
public struct SceneSnapshotEntry: Sendable, Hashable {
    /// SCN-008-R11: reserved for a later MIDI/OSC row that recalls a snapshot; nothing reads it yet.
    public static let recallActionID = "scene.snapshot.recall"

    /// Every field of the entry object, known and unknown, verbatim.
    public var fields: [String: SceneJSON]

    public init(fields: [String: SceneJSON]) {
        self.fields = fields
    }

    /// The entry for a snapshot (values in the `parameters` form).
    public init(_ snapshot: SceneSnapshot) {
        var values: [String: SceneJSON] = [:]
        for (id, value) in snapshot.values { values[id.rawValue] = SceneEncoder.parameterValue(value) }
        fields = ["name": .string(snapshot.name), "values": .object(values)]
    }

    /// The stored name when it is a string (shown even for an unusable entry).
    public var name: String? { fields["name"]?.stringValue }

    var json: SceneJSON { .object(fields) }

    static func decode(_ value: SceneJSON, path: String) throws(SceneDecodeError) -> SceneSnapshotEntry {
        guard let o = value.objectValue else { throw .malformed(path: path, reason: "expected an object, found \(value.typeName)") }
        return SceneSnapshotEntry(fields: o)
    }

    /// The snapshots of `entries` by position (nil for an unusable entry or a position past the limit) and the
    /// warnings for the ones that cannot be used, in order (contract N3).
    public static func read(_ entries: [SceneSnapshotEntry]) -> (snapshots: [SceneSnapshot?], issues: [SceneIssue]) {
        var snapshots: [SceneSnapshot?] = []
        var issues: [SceneIssue] = []
        for (i, entry) in entries.enumerated() {
            let path = "$.snapshots[\(i)]"
            guard i < SceneLimits.maximumSnapshots else {
                issues.append(SceneIssue(.invalidSnapshot, path: path,
                                         "Snapshot \(i + 1) is beyond the limit of \(SceneLimits.maximumSnapshots); it is kept but not used."))
                snapshots.append(nil)
                continue
            }
            let read: (snapshot: SceneSnapshot?, issue: SceneIssue?) = entry.snapshot(at: path, number: i + 1)
            if let issue = read.issue { issues.append(issue) }
            snapshots.append(read.snapshot)
        }
        return (snapshots, issues)
    }

    /// `unknownSnapshotParameter` for every value of a usable snapshot whose ID `registry` does not know (contract N4).
    public static func unknownParameters(_ entries: [SceneSnapshotEntry], registry: ParameterRegistry) -> [SceneIssue] {
        var issues: [SceneIssue] = []
        for (i, snapshot) in read(entries).snapshots.enumerated() {
            guard let snapshot else { continue }
            for id in snapshot.values.keys.sorted() where !registry.contains(id) {
                issues.append(SceneIssue(.unknownSnapshotParameter, path: ScenePath.key("$.snapshots[\(i)].values", id.rawValue),
                                         "Snapshot \"\(snapshot.name)\" sets \"\(id)\", unknown to this version; that value is kept but not recalled."))
            }
        }
        return issues
    }

    private func snapshot(at path: String, number: Int) -> (snapshot: SceneSnapshot?, issue: SceneIssue?) {
        func invalid(_ at: String, _ what: String) -> (snapshot: SceneSnapshot?, issue: SceneIssue?) {
            (nil, SceneIssue(.invalidSnapshot, path: at, "Snapshot \(number): \(what); it is kept but not used."))
        }
        guard let name = fields["name"]?.stringValue, SceneSnapshotEditing.isValidName(name) else {
            return invalid(ScenePath.key(path, "name"), "\"name\" must be text of 1 to \(SceneLimits.maximumSnapshotNameLength) characters")
        }
        guard let object = fields["values"]?.objectValue else {
            return invalid(ScenePath.key(path, "values"), "\"values\" must be an object")
        }
        guard object.count <= SceneLimits.maximumSnapshotValues else {
            return invalid(ScenePath.key(path, "values"), "it has \(object.count) values; at most \(SceneLimits.maximumSnapshotValues) are allowed")
        }
        var values: [ParameterID: ParameterValue] = [:]
        for key in object.keys.sorted() {
            guard let value = object[key].flatMap(Self.parameterValue) else {
                return invalid(ScenePath.key(ScenePath.key(path, "values"), key), "the value of \"\(key)\" is not a parameter value")
            }
            values[ParameterID(key)] = value
        }
        return (SceneSnapshot(name: name, values: values), nil)
    }

    /// A `{"kind": …, "value": …}` object, read leniently (nil for anything else).
    static func parameterValue(_ json: SceneJSON) -> ParameterValue? {
        guard let o = json.objectValue, let kind = o["kind"]?.stringValue, let v = o["value"] else { return nil }
        switch kind {
        case "continuous":
            guard let d = v.numberValue?.doubleValue, d.isFinite else { return nil }
            return .continuous(d)
        case "integer":
            guard let i = v.numberValue?.int64Value, let int = Int(exactly: i) else { return nil }
            return .integer(int)
        case "boolean":
            return v.boolValue.map { (b: Bool) -> ParameterValue in .boolean(b) }
        case "enum":
            return v.stringValue.map { (s: String) -> ParameterValue in .enumeration(s) }
        case "color":
            guard let items = v.arrayValue, items.count == 4 else { return nil }
            var c: [Double] = []
            for item in items {
                guard let d = item.numberValue?.doubleValue, d.isFinite else { return nil }
                c.append(d)
            }
            return .color(ParameterColor(red: c[0], green: c[1], blue: c[2], alpha: c[3]))
        default:
            return nil
        }
    }
}

/// A usable snapshot: its name and values (IDs not checked against a registry).
public struct SceneSnapshot: Sendable, Hashable {
    public var name: String
    public var values: [ParameterID: ParameterValue]

    public init(name: String, values: [ParameterID: ParameterValue]) {
        self.name = name
        self.values = values
    }
}

extension SceneLimits {
    /// SCN-008-R3: snapshots a scene uses (and entries Save allows); entries past it are kept, not used.
    public static let maximumSnapshots = 16
    /// SCN-008-R3: entries in `snapshots` the decoder accepts at all.
    public static let maximumSnapshotEntries = 64
    /// SCN-008-R3: values in one snapshot.
    public static let maximumSnapshotValues = 64
    /// SCN-008: a snapshot name's length in characters, after trimming spaces.
    public static let maximumSnapshotNameLength = 64
}

extension SceneDocument {
    /// SCN-008: the usable snapshots of the document by position (empty without a `snapshots` list).
    public var usableSnapshots: [SceneSnapshot?] { SceneSnapshotEntry.read(snapshots ?? []).snapshots }
}

// MARK: - Editing (contract N6)

public enum SceneSnapshotEditError: Error, Sendable, Hashable, CustomStringConvertible {
    case limitReached
    case invalidName
    case duplicateName
    case noSuchSnapshot

    public var description: String {
        switch self {
        case .limitReached: "A scene holds at most \(SceneLimits.maximumSnapshots) snapshots."
        case .invalidName: "A snapshot name is 1 to \(SceneLimits.maximumSnapshotNameLength) characters."
        case .duplicateName: "Another snapshot already has that name."
        case .noSuchSnapshot: "That snapshot no longer exists."
        }
    }
}

public enum SceneSnapshotEditing {
    /// The name with leading and trailing spaces (and other white space) removed.
    public static func trimmed(_ name: String) -> String {
        var scalars = Substring(name)
        while let first = scalars.first, first.isWhitespace { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.isWhitespace { scalars = scalars.dropLast() }
        return String(scalars)
    }

    /// 1…64 characters, already trimmed.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= SceneLimits.maximumSnapshotNameLength && trimmed(name) == name
    }

    /// "Snapshot N" with the smallest unused N ≥ 1 (compared case-insensitively).
    public static func nextDefaultName(in entries: [SceneSnapshotEntry]) -> String {
        let used: Set<String> = Set(entries.compactMap { (e: SceneSnapshotEntry) -> String? in e.name?.lowercased() })
        var n = 1
        while used.contains("snapshot \(n)") { n += 1 }
        return "Snapshot \(n)"
    }

    /// `entries` with a new snapshot appended.
    public static func adding(_ snapshot: SceneSnapshot, to entries: [SceneSnapshotEntry]) throws(SceneSnapshotEditError) -> [SceneSnapshotEntry] {
        guard entries.count < SceneLimits.maximumSnapshots else { throw .limitReached }
        let name = try checkedName(snapshot.name, in: entries, except: nil)
        return entries + [SceneSnapshotEntry(SceneSnapshot(name: name, values: snapshot.values))]
    }

    /// `entries` with entry `index` renamed; every other field of that entry is kept.
    public static func renaming(at index: Int, to name: String, in entries: [SceneSnapshotEntry]) throws(SceneSnapshotEditError) -> [SceneSnapshotEntry] {
        guard entries.indices.contains(index) else { throw .noSuchSnapshot }
        let checked = try checkedName(name, in: entries, except: index)
        var result = entries
        result[index].fields["name"] = .string(checked)
        return result
    }

    /// `entries` without entry `index`.
    public static func removing(at index: Int, from entries: [SceneSnapshotEntry]) throws(SceneSnapshotEditError) -> [SceneSnapshotEntry] {
        guard entries.indices.contains(index) else { throw .noSuchSnapshot }
        var result = entries
        result.remove(at: index)
        return result
    }

    private static func checkedName(_ name: String, in entries: [SceneSnapshotEntry], except: Int?) throws(SceneSnapshotEditError) -> String {
        let t = trimmed(name)
        guard isValidName(t) else { throw .invalidName }
        let lowered = t.lowercased()
        for (i, entry) in entries.enumerated() where i != except && entry.name?.lowercased() == lowered { throw .duplicateName }
        return t
    }
}

// MARK: - Recall plan (contract N7; research SCN-008-D4)

public enum SceneSnapshotSkipReason: Sendable, Hashable {
    /// The registry does not know the parameter ID.
    case unknownParameter
    /// The registry knows it but the app has no control that sets it.
    case notSettable
    /// The registry refused the value (wrong kind, unknown case); the message says why.
    case rejected(String)
}

/// What a recall writes (validated, clamped as MOD-001 restore clamps; sorted by ID) and what it skips.
public struct SceneSnapshotRecallPlan: Sendable, Equatable {
    public struct Write: Sendable, Equatable {
        public let id: ParameterID
        public let value: ParameterValue
    }

    public struct Skip: Sendable, Equatable {
        public let id: ParameterID
        public let reason: SceneSnapshotSkipReason
    }

    public let writes: [Write]
    public let skipped: [Skip]

    /// `settable` is whether the app can set an ID (registry IDs without an app control are skipped).
    public init(_ snapshot: SceneSnapshot, registry: ParameterRegistry, settable: (ParameterID) -> Bool) {
        let scratch = ParameterStore(registry: registry)
        var writes: [Write] = []
        var skipped: [Skip] = []
        for id in snapshot.values.keys.sorted() {
            guard let value = snapshot.values[id] else { continue }
            guard registry.contains(id) else {
                skipped.append(Skip(id: id, reason: .unknownParameter))
                continue
            }
            guard settable(id) else {
                skipped.append(Skip(id: id, reason: .notSettable))
                continue
            }
            do {
                writes.append(Write(id: id, value: try scratch.set(value, for: id)))
            } catch {
                skipped.append(Skip(id: id, reason: .rejected(error.description)))
            }
        }
        self.writes = writes
        self.skipped = skipped
    }
}
