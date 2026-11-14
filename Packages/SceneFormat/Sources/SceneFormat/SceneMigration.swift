// SceneMigration.swift — older scene format versions to the current one, with an audit log
// (SCN-013-R1 to R6, R14; specs/081-scn-013-scene-migration, contracts/scene-migration.md M1-M3;
// research SCN-013-D2, D3; ADR-0028 amendment).
//
// * A step migrates the raw document object of version N to version N+1 before typed decoding, so an
//   old shape never has to decode with today's typed decoder. Steps are pure, keep every field they do
//   not name (unknown fields included, numbers as written) and record each change they make.
// * The migrator checks the format and version, runs the steps in order from the stored version to its
//   target, writes `version` after each step and returns the migrated value with the audit log.
// * Version 1 is the only version ever written (audit of 2026-11-13, research SCN-013-D1), so the
//   production chain `SceneMigrator.standard` has no steps. Tests prove the mechanism with synthetic
//   chains that are never registered here.
// Plain Swift, no Foundation: no files, no networking, nothing from a document is executed.

/// One change a step made, in the SCN-001 path form (`$.layers[0].values`).
public struct SceneMigrationChange: Sendable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// A value moved from `path` to `newPath` unchanged.
        case renamed
        /// A value was added (a new field with its default).
        case added
        /// A value was removed.
        case removed
        /// A value at `path` was rewritten in place (a new spelling, unit or structure).
        case transformed
        /// The document's `version` changed (written by the migrator after each step).
        case version
    }

    public let kind: Kind
    public let path: String
    /// The new location of a renamed value.
    public let newPath: String?
    public let detail: String

    public init(_ kind: Kind, path: String, newPath: String? = nil, detail: String) {
        self.kind = kind
        self.path = path
        self.newPath = newPath
        self.detail = detail
    }

    public var description: String {
        let target = newPath.map { (p: String) -> String in " -> " + p } ?? ""
        return "\(kind.rawValue) \(path)\(target): \(detail)"
    }
}

/// One audit log line: which step made which change.
public struct SceneMigrationLogEntry: Sendable, Hashable, CustomStringConvertible {
    public let step: String
    public let fromVersion: Int
    public let toVersion: Int
    public let change: SceneMigrationChange

    public init(step: String, fromVersion: Int, toVersion: Int, change: SceneMigrationChange) {
        self.step = step
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.change = change
    }

    public var description: String { "v\(fromVersion)->v\(toVersion) \(step): \(change)" }
}

/// Collects the changes of the step that is running.
public struct SceneMigrationRecorder: Sendable {
    public private(set) var changes: [SceneMigrationChange] = []

    public init() {}

    public mutating func renamed(_ path: String, to newPath: String, _ detail: String) {
        changes.append(SceneMigrationChange(.renamed, path: path, newPath: newPath, detail: detail))
    }

    public mutating func added(_ path: String, _ detail: String) {
        changes.append(SceneMigrationChange(.added, path: path, detail: detail))
    }

    public mutating func removed(_ path: String, _ detail: String) {
        changes.append(SceneMigrationChange(.removed, path: path, detail: detail))
    }

    public mutating func transformed(_ path: String, _ detail: String) {
        changes.append(SceneMigrationChange(.transformed, path: path, detail: detail))
    }
}

/// Why a document could not be migrated (mapped to `SceneDecodeError` by `decode`).
public enum SceneMigrationError: Error, Sendable, Hashable, CustomStringConvertible {
    case notAScene
    case invalidVersion(String)
    case newerVersion(Int64)
    /// No step starts at this version, and it is below the target.
    case missingStep(fromVersion: Int64)
    /// A step refused the document.
    case stepFailed(step: String, fromVersion: Int64, path: String, reason: String)

    public var description: String {
        switch self {
        case .notAScene: "not a scene"
        case let .invalidVersion(text): "invalid version \(text)"
        case let .newerVersion(v): "newer version \(v)"
        case let .missingStep(v): "no step from version \(v)"
        case let .stepFailed(step, v, path, reason): "step \(step) from version \(v) failed at \(path): \(reason)"
        }
    }

    var decodeError: SceneDecodeError {
        switch self {
        case .notAScene: .notAScene
        case let .invalidVersion(text): .invalidVersion(text)
        case let .newerVersion(v): .newerVersion(v)
        case let .missingStep(v): .migrationFailed(fromVersion: v, step: nil, path: "$.version", reason: "no step from version \(v)")
        case let .stepFailed(step, v, path, reason): .migrationFailed(fromVersion: v, step: step, path: path, reason: reason)
        }
    }
}

/// One migration from `fromVersion` to `fromVersion + 1`.
public struct SceneMigrationStep: Sendable {
    public typealias Transform = @Sendable ([String: SceneJSON], inout SceneMigrationRecorder) throws(SceneMigrationError)
        -> [String: SceneJSON]

    public let fromVersion: Int
    /// A stable identifier, for example `v1-to-v2`.
    public let identifier: String
    /// What the step changes, in plain words (ADR-0028 lists every step).
    public let summary: String
    let transform: Transform

    /// `transform` receives the document object (with its old `version`) and returns the new object;
    /// it records every renamed, added, removed or transformed value and never sets `version`.
    public init(fromVersion: Int, identifier: String, summary: String, transform: @escaping Transform) {
        self.fromVersion = fromVersion
        self.identifier = identifier
        self.summary = summary
        self.transform = transform
    }
}

/// What a migration did. `migrated` is false for a document already at the target version.
public struct SceneMigrationRecord: Sendable, Hashable {
    public let sourceVersion: Int
    public let targetVersion: Int
    public let log: [SceneMigrationLogEntry]

    public init(sourceVersion: Int, targetVersion: Int, log: [SceneMigrationLogEntry]) {
        self.sourceVersion = sourceVersion
        self.targetVersion = targetVersion
        self.log = log
    }

    /// A current-version document: nothing ran.
    public static func unchanged(version: Int) -> SceneMigrationRecord {
        SceneMigrationRecord(sourceVersion: version, targetVersion: version, log: [])
    }

    public var migrated: Bool { sourceVersion != targetVersion }
    /// Steps that ran.
    public var stepCount: Int { targetVersion - sourceVersion }
    /// Changes the steps recorded (the migrator's version entries are not counted).
    public var changeCount: Int { log.filter { (e: SceneMigrationLogEntry) -> Bool in e.change.kind != .version }.count }

    /// SCN-013-R8: the name of the original's backup next to a stored file (`current.scene.v1.backup`).
    public func backupName(for fileName: String) -> String { Self.backupName(for: fileName, version: sourceVersion) }

    public static func backupName(for fileName: String, version: Int) -> String { fileName + ".v\(version).backup" }

    /// Whether `name` is a backup of `fileName` (any version).
    public static func isBackup(_ name: String, of fileName: String) -> Bool {
        let prefix = fileName + ".v"
        let suffix = ".backup"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { return false }
        let digits = name.dropFirst(prefix.count).dropLast(suffix.count)
        return digits.allSatisfy { (c: Character) -> Bool in c.isASCII && c.isNumber }
    }

    /// Diagnostics text without scene content (SCN-013-R10).
    public var summary: String {
        "migrated scene from version \(sourceVersion) to \(targetVersion) (\(stepCount) steps, \(changeCount) changes)"
    }
}

public struct SceneMigrationResult: Sendable {
    public let root: SceneJSON
    public let record: SceneMigrationRecord
}

/// An ordered chain of steps up to `targetVersion`.
public struct SceneMigrator: Sendable {
    public let steps: [SceneMigrationStep]
    public let targetVersion: Int

    /// The app's chain. Empty: version 1 is the only version ever written (research SCN-013-D1).
    /// A format change appends its step here (procedure in ADR-0028's SCN-013 amendment).
    public static let standard = SceneMigrator(steps: [], targetVersion: SceneDocument.currentVersion)

    public init(steps: [SceneMigrationStep], targetVersion: Int) {
        self.steps = steps
        self.targetVersion = targetVersion
    }

    /// The oldest version this chain reads.
    public var oldestVersion: Int { steps.map(\.fromVersion).min() ?? targetVersion }

    /// Checks the format and version, then runs the chain (contract M2, M3).
    public func migrate(_ root: SceneJSON) throws(SceneMigrationError) -> SceneMigrationResult {
        guard var object = root.objectValue, object["format"]?.stringValue == SceneDocument.formatName else { throw .notAScene }
        guard let versionValue = object["version"] else { throw .invalidVersion("nothing") }
        guard let number = versionValue.numberValue else { throw .invalidVersion(versionValue.typeName) }
        guard let stored = number.int64Value else { throw .invalidVersion(number.text) }
        guard stored <= Int64(targetVersion) else { throw .newerVersion(stored) }
        let hasStep = steps.contains { (s: SceneMigrationStep) -> Bool in Int64(s.fromVersion) == stored }
        guard stored >= 1 || hasStep else { throw .invalidVersion(number.text) }

        let source = Int(stored)
        var version = source
        var log: [SceneMigrationLogEntry] = []
        while version < targetVersion {
            guard let step = steps.first(where: { (s: SceneMigrationStep) -> Bool in s.fromVersion == version }) else {
                throw .missingStep(fromVersion: Int64(version))
            }
            var recorder = SceneMigrationRecorder()
            var next = try step.transform(object, &recorder)
            let to = version + 1
            next["version"] = .integer(Int64(to))
            for change in recorder.changes {
                log.append(SceneMigrationLogEntry(step: step.identifier, fromVersion: version, toVersion: to, change: change))
            }
            log.append(SceneMigrationLogEntry(step: step.identifier, fromVersion: version, toVersion: to,
                                              change: SceneMigrationChange(.version, path: "$.version", detail: "\(version) to \(to)")))
            object = next
            version = to
        }
        return SceneMigrationResult(root: .object(object),
                                    record: SceneMigrationRecord(sourceVersion: source, targetVersion: targetVersion, log: log))
    }
}

/// Paths in the SCN-001 form, for steps written outside this module.
public enum SceneJSONPath {
    public static let root = "$"
    public static func key(_ base: String, _ key: String) -> String { ScenePath.key(base, key) }
    public static func index(_ base: String, _ i: Int) -> String { ScenePath.index(base, i) }
}
