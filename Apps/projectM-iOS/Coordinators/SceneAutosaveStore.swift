// SceneAutosaveStore.swift — the current scene's files, crash-safe atomic saves and a validated load
// with fallback (SCN-002-R5 to R7, R13; research SCN-002-D4, D5; contracts/scene-autosave.md A1-A3).
//
// * Folder `Library/Application Support/Scenes` (private, in the user's own device backups):
//   `current.scene` (main), `current.scene.bak` (the previous committed scene), `current.scene.tmp`
//   (only during a save) and `<name>.newer` (a file from a newer app version, set aside once).
// * Save (A2): write the temporary file, F_FULLFSYNC it (fsync if refused), remove the old backup and
//   hard-link the main file as the backup (only while the main file is known good), rename the
//   temporary file over the main file (rename(2) is atomic within the volume), fsync the folder. After
//   the first commit, at least one complete committed scene exists at every step; a failed step throws
//   and removes the temporary file. `Data.write(options: .atomic)` is not used: no flush promise.
// * Load (A3): a leftover temporary file is removed and never read; main then backup are read through
//   a file handle (at most 1 MiB + 1 byte; no attributes or timestamps: required-reason APIs), decoded
//   and turned into live state by SCN-001 (validation, MOD-013 restore). Failures are events, never
//   errors, never UI.
// * SCN-013 (contract M4, M5): decoding migrates an older format version in memory; loading never
//   writes. Before the first save that replaces or removes a migrated main or backup file, its original
//   bytes are written once to `<name>.v<N>.backup` (exclusive create, F_FULLFSYNC; an existing backup
//   is kept, never overwritten); if that fails the save is refused at step `keepOriginal` and nothing
//   else changes. Events name versions, counts and fixed file names only.
// * Thread use: `load` at launch, then `save` only on the coordinator's serial queue.
import Foundation
import ParameterGraph
import SceneFormat

enum SceneAutosaveSource: String, Sendable, Equatable {
    case main, backup, none
}

enum SceneAutosaveEvent: Sendable, Equatable, CustomStringConvertible {
    case mainUnreadable(String)
    case backupUnreadable(String)
    case restoredFromBackup
    case nothingRestored
    /// A file written by a newer app version was moved aside (its new name).
    case setAsideNewer(String)
    case writeFailed(String)
    case droppedLayers(Int)
    case renumberedLayer(UInt64)
    /// SCN-013: a file of an older format version was migrated in memory (no scene content).
    case migrated(from: Int, to: Int, steps: Int, changes: Int)
    /// SCN-013: the original of a migrated file was kept under this name before it was replaced.
    case keptOriginal(String)

    var description: String {
        switch self {
        case let .mainUnreadable(reason): "main unreadable: \(reason)"
        case let .backupUnreadable(reason): "backup unreadable: \(reason)"
        case .restoredFromBackup: "restored from backup"
        case .nothingRestored: "nothing restored"
        case let .setAsideNewer(name): "set aside newer-version file as \(name)"
        case let .writeFailed(step): "write failed at \(step)"
        case let .droppedLayers(count): "dropped \(count) layer(s) beyond the stack limit"
        case let .renumberedLayer(instance): "renumbered kept layer \(instance)"
        case let .migrated(from, to, steps, changes): "migrated scene from version \(from) to \(to) (\(steps) steps, \(changes) changes)"
        case let .keptOriginal(name): "kept original as \(name)"
        }
    }
}

struct SceneAutosaveLoad: Sendable {
    let document: SceneDocument?
    let result: SceneLoadResult?
    let source: SceneAutosaveSource
    let events: [SceneAutosaveEvent]
}

enum SceneAutosaveStep: String, Sendable, CaseIterable {
    case writeTemporary, flushTemporary, removeBackup, linkBackup, replaceMain, flushFolder
    /// SCN-013: writing the original of a migrated file before it is replaced (only when one is pending).
    case keepOriginal
}

struct SceneAutosaveWriteError: Error, Sendable, Equatable {
    let step: SceneAutosaveStep
    let code: Int32
}

/// `@unchecked Sendable`: `mainIsGood` and `fault` are used from one queue at a time (launch, then the
/// coordinator's serial queue; tests call it from one thread).
final class SceneAutosaveStore: @unchecked Sendable {
    static let folderName = "Scenes"
    static let mainName = "current.scene"
    static let backupName = "current.scene.bak"
    static let temporaryName = "current.scene.tmp"
    static let newerSuffix = ".newer"

    let directory: URL
    /// The scene migration chain (the app's; tests pass synthetic chains, SCN-013).
    let migrator: SceneMigrator
    var main: URL { directory.appendingPathComponent(Self.mainName, isDirectory: false) }
    var backup: URL { directory.appendingPathComponent(Self.backupName, isDirectory: false) }
    var temporary: URL { directory.appendingPathComponent(Self.temporaryName, isDirectory: false) }

    /// The main file was read good or written by this process; only then is it linked as the backup.
    private(set) var mainIsGood = false
    /// Tests: called before each step; throwing simulates a failure (or a kill) at that point.
    var fault: (@Sendable (SceneAutosaveStep) throws -> Void)?
    /// SCN-013: originals of migrated files read by `load`, kept before the next save changes any file.
    private(set) var pendingOriginals: [PendingOriginal] = []
    /// Names of originals kept by `save` and not yet reported (`takeKeptOriginals`).
    private var keptNames: [String] = []

    struct PendingOriginal: Sendable, Equatable {
        let fileName: String
        let bytes: [UInt8]
        let sourceVersion: Int
    }

    init(directory: URL, migrator: SceneMigrator = .standard) {
        self.directory = directory
        self.migrator = migrator
    }

    /// `Library/Application Support/Scenes`.
    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: - Load (A3)

    func load(registry: ParameterRegistry, assets availability: (any SceneAssetAvailability)?) -> SceneAutosaveLoad {
        _ = unlink(temporary.path)   // a killed save's leftover is never read
        var events: [SceneAutosaveEvent] = []
        pendingOriginals = []
        switch read(main, registry: registry, assets: availability) {
        case let .success(loaded):
            mainIsGood = true
            events += noteMigration(loaded, fileName: Self.mainName)
            // The backup is removed by the next save while the main is good: keep a migrated backup too.
            noteMigratedBackup()
            return SceneAutosaveLoad(document: loaded.document, result: loaded.result, source: .main, events: events)
        case let .failure(problem):
            mainIsGood = false
            if problem != .absent {
                events.append(.mainUnreadable(problem.reason))
                if problem.isNewerVersion, let name = setAside(main) { events.append(.setAsideNewer(name)) }
            }
            switch read(backup, registry: registry, assets: availability) {
            case let .success(loaded):
                events.append(.restoredFromBackup)
                events += noteMigration(loaded, fileName: Self.backupName)
                return SceneAutosaveLoad(document: loaded.document, result: loaded.result, source: .backup, events: events)
            case let .failure(backupProblem):
                if backupProblem != .absent {
                    events.append(.backupUnreadable(backupProblem.reason))
                    if backupProblem.isNewerVersion, let name = setAside(backup) { events.append(.setAsideNewer(name)) }
                }
                if !events.isEmpty { events.append(.nothingRestored) }
                return SceneAutosaveLoad(document: nil, result: nil, source: .none, events: events)
            }
        }
    }

    private enum ReadProblem: Error, Equatable {
        case absent
        case unreadable
        case tooLarge
        case decode(SceneDecodeError)
        case invalid([String])

        var reason: String {
            switch self {
            case .absent: "absent"
            case .unreadable: "cannot be read"
            case .tooLarge: "larger than \(SceneLimits.maximumBytes) bytes"
            case let .decode(error): error.message
            case let .invalid(codes): "invalid (" + codes.joined(separator: ", ") + ")"
            }
        }

        var isNewerVersion: Bool { if case .decode(.newerVersion) = self { true } else { false } }
    }

    private struct Loaded {
        let document: SceneDocument
        let result: SceneLoadResult
        let migration: SceneMigrationRecord
        let bytes: [UInt8]
    }

    /// The backup while the main file is good: only its version is checked (it is not opened).
    private func noteMigratedBackup() {
        guard let handle = try? FileHandle(forReadingFrom: backup) else { return }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: SceneLimits.maximumBytes + 1), data.count <= SceneLimits.maximumBytes,
              let root = try? SceneJSON.parse([UInt8](data)), let record = try? migrator.migrate(root).record, record.migrated else { return }
        pendingOriginals.append(PendingOriginal(fileName: Self.backupName, bytes: [UInt8](data), sourceVersion: record.sourceVersion))
    }

    /// Records a migrated file's original for the next save and returns its event.
    private func noteMigration(_ loaded: Loaded, fileName: String) -> [SceneAutosaveEvent] {
        let record = loaded.migration
        guard record.migrated else { return [] }
        pendingOriginals.append(PendingOriginal(fileName: fileName, bytes: loaded.bytes, sourceVersion: record.sourceVersion))
        return [.migrated(from: record.sourceVersion, to: record.targetVersion, steps: record.stepCount, changes: record.changeCount)]
    }

    private func read(_ url: URL, registry: ParameterRegistry,
                      assets availability: (any SceneAssetAvailability)?) -> Result<Loaded, ReadProblem> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.absent) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.unreadable) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: SceneLimits.maximumBytes + 1) else {
            return .failure(.decode(.empty))   // an empty file reads as nil
        }
        guard data.count <= SceneLimits.maximumBytes else { return .failure(.tooLarge) }
        let decoded: SceneDecodeResult
        do {
            decoded = try SceneDocument.decode([UInt8](data), migrator: migrator)
        } catch {
            return .failure(.decode(error))
        }
        do {
            let result = try decoded.document.liveState(registry: registry, assets: availability)
            return .success(Loaded(document: decoded.document, result: result, migration: decoded.migration, bytes: [UInt8](data)))
        } catch {
            switch error {
            case let .invalid(issues):
                return .failure(.invalid(issues.map { (i: SceneIssue) -> String in i.code.rawValue }))
            }
        }
    }

    /// Moves a newer-version file to `<name>.newer` unless that name exists; returns the new name.
    private func setAside(_ url: URL) -> String? {
        let target = url.path + Self.newerSuffix
        guard !FileManager.default.fileExists(atPath: target) else { return nil }
        guard rename(url.path, target) == 0 else { return nil }
        return (target as NSString).lastPathComponent
    }

    // MARK: - Save (A2)

    func save(_ bytes: [UInt8]) throws(SceneAutosaveWriteError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw SceneAutosaveWriteError(step: .writeTemporary, code: -1)
        }
        do throws(SceneAutosaveWriteError) {
            try keepPendingOriginals()
            try writeTemporary(bytes)
            if mainIsGood && FileManager.default.fileExists(atPath: main.path) {
                try step(.removeBackup) { () -> Int32 in
                    let r = unlink(self.backup.path)
                    return (r == 0 || errno == ENOENT) ? 0 : -1
                }
                try step(.linkBackup) { () -> Int32 in link(self.main.path, self.backup.path) }
            }
            try step(.replaceMain) { () -> Int32 in rename(self.temporary.path, self.main.path) }
        } catch {
            _ = unlink(temporary.path)
            throw error
        }
        mainIsGood = true
        // The rename stands even if the folder flush fails (a later commit flushes again).
        try? step(.flushFolder) { () -> Int32 in
            let fd = open(self.directory.path, O_RDONLY)
            guard fd >= 0 else { return -1 }
            defer { close(fd) }
            return fsync(fd)
        }
    }

    // MARK: - Originals of migrated files (SCN-013)

    /// Writes each pending original to `<name>.v<N>.backup` before anything else changes; an existing
    /// backup is kept. Throws (and keeps the rest pending) when one cannot be written.
    private func keepPendingOriginals() throws(SceneAutosaveWriteError) {
        while let pending = pendingOriginals.first {
            try fault(.keepOriginal)
            let name = SceneMigrationRecord.backupName(for: pending.fileName, version: pending.sourceVersion)
            let path = directory.appendingPathComponent(name, isDirectory: false).path
            let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd < 0 {
                guard errno == EEXIST else { throw SceneAutosaveWriteError(step: .keepOriginal, code: errno) }
                var info = stat()
                guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
                    throw SceneAutosaveWriteError(step: .keepOriginal, code: EEXIST)
                }
            } else {
                do throws(SceneAutosaveWriteError) {
                    try writeAll(fd, pending.bytes, step: .keepOriginal)
                    if fcntl(fd, F_FULLFSYNC) == -1 && fsync(fd) == -1 {
                        throw SceneAutosaveWriteError(step: .keepOriginal, code: errno)
                    }
                } catch {
                    close(fd)
                    _ = unlink(path)
                    throw error
                }
                guard close(fd) == 0 else {
                    _ = unlink(path)
                    throw SceneAutosaveWriteError(step: .keepOriginal, code: errno)
                }
                keptNames.append(name)
            }
            pendingOriginals.removeFirst()
        }
    }

    /// Names kept since the last call (the coordinator records them as events).
    func takeKeptOriginals() -> [String] {
        defer { keptNames = [] }
        return keptNames
    }

    private func writeAll(_ fd: Int32, _ bytes: [UInt8], step: SceneAutosaveStep) throws(SceneAutosaveWriteError) {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
                write(fd, raw.baseAddress! + offset, bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw SceneAutosaveWriteError(step: step, code: errno)
            }
            offset += written
        }
    }

    private func writeTemporary(_ bytes: [UInt8]) throws(SceneAutosaveWriteError) {
        try fault(.writeTemporary)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw SceneAutosaveWriteError(step: .writeTemporary, code: errno) }
        var closed = false
        defer { if !closed { close(fd) } }
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
                write(fd, raw.baseAddress! + offset, bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw SceneAutosaveWriteError(step: .writeTemporary, code: errno)
            }
            offset += written
        }
        try fault(.flushTemporary)
        // F_FULLFSYNC asks the drive to flush its cache; fsync when the file system refuses it.
        if fcntl(fd, F_FULLFSYNC) == -1 && fsync(fd) == -1 {
            throw SceneAutosaveWriteError(step: .flushTemporary, code: errno)
        }
        closed = true
        guard close(fd) == 0 else { throw SceneAutosaveWriteError(step: .flushTemporary, code: errno) }
    }

    private func fault(_ step: SceneAutosaveStep) throws(SceneAutosaveWriteError) {
        guard let fault else { return }
        do {
            try fault(step)
        } catch {
            throw SceneAutosaveWriteError(step: step, code: -2)
        }
    }

    private func step(_ step: SceneAutosaveStep, _ body: () -> Int32) throws(SceneAutosaveWriteError) {
        try fault(step)
        guard body() == 0 else { throw SceneAutosaveWriteError(step: step, code: errno) }
    }

    // MARK: - Reset

    /// UI tests (`-uitestResetNotice`): no scene files.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        mainIsGood = false
    }
}
