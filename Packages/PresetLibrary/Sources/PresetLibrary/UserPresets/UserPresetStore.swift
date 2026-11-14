// UserPresetStore.swift — the files of the user's imported presets (PRE-012-R4, R17, R18, R25;
// contracts/user-presets.md).
//
// Layout under `directory` (Application Support/UserPresets in the app):
//   index.json                 the versioned record, only ever replaced atomically
//   index.unreadable.json      an unreadable record, set aside (one copy is kept)
//   files/<sha256>.milk        copies of waiting and playable presets
//   quarantine/<sha256>.milk   copies of quarantined files; nothing that plays presets reads here
//   trial.json, proving.json   which preset is being tried / first shown (crash-loop protection)
//   edit.json                  which preset's edited text is being tried (PRE-015-R13)
//   staging/                   FILE-003: texts of an archive install before they move into files/;
//                              exists only during `addAll` (a leftover is removed at load)
//
// * Stored names come from the content hash only; nothing from the picked file's name or
//   location is ever used as a path (R4).
// * Every change is a transaction: files first, then the record; if the record cannot be saved
//   the files are put back and memory is unchanged (R25).
// * A record from a newer app version is never interpreted or written; an unreadable one is set
//   aside, not deleted.
// * Files no record names are left alone.
// * PRE-015-R19: every create, write, move, copy and delete goes through `perform`, which refuses a
//   path that is not inside `directory` (after resolving `..` and symbolic links). Nothing here
//   can touch the app bundle or the preset archive.
// * PRE-015-R14, R22: texts stay content-addressed; `replaceContents` writes the new text, then
//   the record, and deletes the old text last.
// Not Sendable: owned by the `UserPresetLibrary` actor.
import Foundation

public final class UserPresetStore {
    public enum Availability: Equatable, Sendable {
        case available
        case newerFormat(version: Int)
    }

    public enum LoadNotice: Equatable, Sendable {
        case none
        case unreadableSetAside
    }

    public enum StoreError: Error, Equatable, Sendable {
        case newerFormat
        case saveFailed
        case unknownPreset
    }

    public enum Phase: String, Codable, Sendable, CaseIterable {
        /// The off-screen trial is running (R17).
        case trial
        /// The preset is on the visible renderer for the first time (R18).
        case proving
        /// An edited text of the preset is being tried; the stored text is unchanged (PRE-015-R13).
        case editCheck

        var fileName: String { self == .editCheck ? "edit.json" : rawValue + ".json" }
    }

    public struct LeftoverRecord: Equatable, Sendable {
        public let phase: Phase
        public let presetID: String
        /// For `editCheck`: the hash of the text that was being tried.
        public var candidateSHA256: String?
    }

    private struct TrialRecord: Codable {
        var schemaVersion = 1
        var presetID: String
        var phase: Phase
        var candidateSHA256: String?
    }

    /// What `perform` did (PRE-015-T04).
    public enum FileOperation: Equatable, Sendable {
        case createDirectory, write, move, copy, remove
    }

    public static let directoryName = "UserPresets"
    public static let indexFileName = "index.json"
    public static let unreadableFileName = "index.unreadable.json"
    static let filesFolder = "files"
    static let quarantineFolder = "quarantine"
    /// FILE-003-R9: where `addAll` stages texts (inside `directory`, so the path guard covers it).
    static let stagingFolder = "staging"
    /// FILE-004: inside `staging/`, the old texts a Replace install leaves unnamed once committed.
    static let replacedListName = "replaced.json"

    /// `<Application Support>/UserPresets`. Created on the first save.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// In import order. Empty while unavailable.
    public private(set) var presets: [UserPreset] = []
    public let availability: Availability
    public private(set) var loadNotice: LoadNotice = .none

    private let directory: URL
    private let indexURL: URL
    private let write: (Data, URL) throws -> Void
    /// Sees every file operation before it is performed (tests, PRE-015-S3).
    var fileOperationObserver: ((FileOperation, URL) -> Void)?
    /// FILE-003 tests: may throw before an operation is performed (an injected fault).
    var fileOperationFault: ((FileOperation, URL) throws -> Void)?
    private var migrationBackup: URL?
    /// An unreadable record could not be moved aside: saving would destroy it.
    private var savingBlocked = false

    public init(directory: URL,
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                migrations: [Int: UserPresetsFile.Migration] = UserPresetsFile.migrations,
                observer: ((FileOperation, URL) -> Void)? = nil) {
        self.directory = directory
        self.write = write
        fileOperationObserver = observer
        indexURL = directory.appendingPathComponent(Self.indexFileName)
        let files = FileManager.default
        guard files.fileExists(atPath: indexURL.path) else {
            availability = .available
            return
        }
        do {
            let loaded = try UserPresetsFile.decode(Data(contentsOf: indexURL), migrations: migrations)
            availability = .available
            presets = loaded.file.presets
            if let from = loaded.migratedFrom { saveMigrated(from: from) }
        } catch UserPresetsFile.ReadError.newerVersion(let version) {
            availability = .newerFormat(version: version)
        } catch {
            availability = .available
            let aside = directory.appendingPathComponent(Self.unreadableFileName)
            try? removeFile(at: aside)
            loadNotice = .unreadableSetAside
            if (try? moveFile(indexURL, to: aside)) == nil { savingBlocked = true }
        }
    }

    // MARK: - Reading

    public func preset(id: String) -> UserPreset? { presets.first { $0.id == id } }
    public func preset(sha256: String) -> UserPreset? { presets.first { $0.sha256 == sha256 } }

    /// The stored bytes, whatever the state. Only `UserPresetLibrary` calls this, and it hands
    /// bytes to a renderer for playable presets alone (R20).
    func contents(of id: String) -> Data? {
        guard let preset = preset(id: id) else { return nil }
        return try? Data(contentsOf: fileURL(preset))
    }

    // MARK: - Changes

    /// Stores the copy, then the record.
    public func add(_ preset: UserPreset, contents: Data) throws {
        try requireWritable()
        guard preset.isWellFormed, self.preset(id: preset.id) == nil, self.preset(sha256: preset.sha256) == nil else {
            throw StoreError.saveFailed
        }
        let url = fileURL(preset)
        let existed = FileManager.default.fileExists(atPath: url.path)
        do {
            try createDirectory(url.deletingLastPathComponent())
            if !existed { try writeFile(contents, to: url) }
        } catch {
            throw StoreError.saveFailed
        }
        guard save(presets + [preset]) else {
            if !existed { try? removeFile(at: url) }
            removeIfEmpty(url.deletingLastPathComponent())
            throw StoreError.saveFailed
        }
        presets.append(preset)
    }

    /// FILE-003-R9 (research FILE-003-D4): adds several waiting or playable presets, all or nothing.
    /// Every text is staged in `staging/` and read back against its SHA-256, the staged files are
    /// moved into `files/`, and the record is written once at the end. Any failure removes every
    /// file and folder this call added, so the directory is byte-for-byte as before, and throws.
    /// A text whose content-addressed file already exists is not written again (as `add`).
    public func addAll(_ items: [(preset: UserPreset, contents: Data)]) throws {
        try commitImport(adding: items, replacing: [])
    }

    /// FILE-004-R6 (research FILE-004-D3): `addAll` plus replacements. Each `replacing` record has the
    /// identifier of a stored preset and describes its new text; it takes that record's place in the
    /// index. Order: stage and verify every new text, write `staging/replaced.json` (the old texts the
    /// commit leaves unnamed), move the staged texts into `files/`, write the index once (the commit),
    /// then delete the old texts and `staging/`. A failure before the commit removes everything this
    /// call added (no old byte was touched) and throws; a failure after it is finished at the next load
    /// (`removeLeftoverStaging`).
    public func commitImport(adding items: [(preset: UserPreset, contents: Data)],
                             replacing replacements: [(preset: UserPreset, contents: Data)]) throws {
        try requireWritable()
        guard !items.isEmpty || !replacements.isEmpty else { return }
        let replacedIDs: Set<String> = Set(replacements.map { (item: (preset: UserPreset, contents: Data)) -> String in item.preset.id })
        guard replacedIDs.count == replacements.count else { throw StoreError.saveFailed }
        var ids = Set(presets.map(\.id))
        var hashes = Set(presets.filter { (preset: UserPreset) -> Bool in !replacedIDs.contains(preset.id) }.map(\.sha256))
        var oldFiles: [URL] = []
        for item in replacements {
            guard let old = preset(id: item.preset.id), old.sha256 != item.preset.sha256 else { throw StoreError.saveFailed }
            oldFiles.append(fileURL(old))
        }
        for item in items + replacements {
            let isReplacement: Bool = replacedIDs.contains(item.preset.id)
            guard item.preset.isWellFormed, item.preset.state != .quarantined,
                  isReplacement || ids.insert(item.preset.id).inserted, hashes.insert(item.preset.sha256).inserted,
                  item.contents.count == item.preset.byteCount,
                  ContentHash.sha256Hex([UInt8](item.contents)) == item.preset.sha256 else { throw StoreError.saveFailed }
        }
        let files = FileManager.default
        let directoryExisted = files.fileExists(atPath: directory.path)
        let filesURL = directory.appendingPathComponent(Self.filesFolder, isDirectory: true)
        let filesExisted = files.fileExists(atPath: filesURL.path)
        let staging = directory.appendingPathComponent(Self.stagingFolder, isDirectory: true)
        var moved: [URL] = []
        func rollback() {
            for url in moved.reversed() { try? removeFile(at: url) }
            if files.fileExists(atPath: staging.path) { try? removeFile(at: staging) }
            if !filesExisted { removeIfEmpty(filesURL) }
            if !directoryExisted { removeIfEmpty(directory) }
        }
        do {
            try createDirectory(staging)
            var staged: [(from: URL, to: URL)] = []
            for item in items + replacements {
                let target = fileURL(item.preset)
                if files.fileExists(atPath: target.path) { continue }
                let file = staging.appendingPathComponent(item.preset.fileName)
                try writeFile(item.contents, to: file)
                guard let back = try? Data(contentsOf: file), ContentHash.sha256Hex([UInt8](back)) == item.preset.sha256 else {
                    throw StoreError.saveFailed
                }
                staged.append((file, target))
            }
            if !oldFiles.isEmpty {
                let list: [String] = oldFiles.map { (url: URL) -> String in url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent }
                try writeFile(try JSONEncoder().encode(list), to: staging.appendingPathComponent(Self.replacedListName))
            }
            try createDirectory(filesURL)
            for step in staged {
                try moveFile(step.from, to: step.to)
                moved.append(step.to)
            }
            // Without replacements `staging/` holds nothing more: removed before the commit (FILE-003).
            if oldFiles.isEmpty { try removeFile(at: staging) }
        } catch {
            rollback()
            throw StoreError.saveFailed
        }
        var draft = presets
        for item in replacements {
            if let index = draft.firstIndex(where: { (preset: UserPreset) -> Bool in preset.id == item.preset.id }) { draft[index] = item.preset }
        }
        draft += items.map(\.preset)
        guard save(draft) else {
            rollback()
            throw StoreError.saveFailed
        }
        presets = draft
        // Committed. Clean-up failures are finished at the next load.
        guard !oldFiles.isEmpty else { return }
        var cleaned = true
        for url in oldFiles {
            if (try? removeFile(at: url)) == nil { cleaned = false; continue }
            removeIfEmpty(url.deletingLastPathComponent())
        }
        if cleaned { try? removeFile(at: staging) }
    }

    /// FILE-003: a `staging/` folder left by an install the app did not finish names no preset
    /// (the record is written last), so it is removed. FILE-004: first, each old text listed in
    /// `staging/replaced.json` that no record names any more (the install committed) is deleted.
    public func removeLeftoverStaging() {
        let staging = directory.appendingPathComponent(Self.stagingFolder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: staging.path) else { return }
        if availability == .available,
           let data = try? Data(contentsOf: staging.appendingPathComponent(Self.replacedListName)),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            let named: Set<String> = Set(presets.map { (preset: UserPreset) -> String in
                let url = fileURL(preset)
                return url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
            })
            for path in list where !named.contains(path) {
                let parts: [String] = path.split(separator: "/").map(String.init)
                guard parts.count == 2, parts[0] == Self.filesFolder || parts[0] == Self.quarantineFolder,
                      Self.isStoredFileName(parts[1]) else { continue }
                let folder = directory.appendingPathComponent(parts[0], isDirectory: true)
                let url = folder.appendingPathComponent(parts[1])
                if FileManager.default.fileExists(atPath: url.path) { try? removeFile(at: url) }
                removeIfEmpty(folder)
            }
        }
        try? removeFile(at: staging)
    }

    /// Changes one record. When the state moves the preset into or out of quarantine, its copy
    /// moves with it. The id, hashes and size cannot be changed.
    public func update(_ id: String, _ change: (inout UserPreset) -> Void) throws {
        try requireWritable()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownPreset }
        let old = presets[index]
        var new = old
        change(&new)
        new.id = old.id; new.sha256 = old.sha256; new.blobHash = old.blobHash; new.byteCount = old.byteCount
        guard new != old else { return }
        guard new.isWellFormed else { throw StoreError.saveFailed }
        let from = fileURL(old), to = fileURL(new)
        var moved = false
        if from != to {
            do {
                try createDirectory(to.deletingLastPathComponent())
                try? removeFile(at: to)
                try moveFile(from, to: to)
                moved = true
            } catch {
                throw StoreError.saveFailed
            }
        }
        var draft = presets
        draft[index] = new
        guard save(draft) else {
            if moved {
                try? moveFile(to, to: from)
                removeIfEmpty(to.deletingLastPathComponent())
            }
            throw StoreError.saveFailed
        }
        presets = draft
    }

    /// Replaces a waiting or playable preset's text (PRE-015-R14). `new` keeps the id and
    /// describes `contents` (hashes, size). Order: new text, record, then the old text is
    /// deleted. If the record cannot be saved the new text is removed and nothing changed.
    public func replaceContents(_ id: String, with new: UserPreset, contents: Data) throws {
        try requireWritable()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownPreset }
        let old = presets[index]
        let bytes = [UInt8](contents)
        guard new.id == id, new.isWellFormed, old.state != .quarantined, new.state != .quarantined,
              new.sha256 != old.sha256, preset(sha256: new.sha256) == nil,
              new.byteCount == bytes.count, new.sha256 == ContentHash.sha256Hex(bytes),
              new.blobHash == ContentHash.gitBlobSHA1Hex(bytes) else { throw StoreError.saveFailed }
        let from = fileURL(old), to = fileURL(new)
        let existed = FileManager.default.fileExists(atPath: to.path)
        do {
            try createDirectory(to.deletingLastPathComponent())
            if !existed { try writeFile(contents, to: to) }
        } catch {
            throw StoreError.saveFailed
        }
        var draft = presets
        draft[index] = new
        guard save(draft) else {
            if !existed { try? removeFile(at: to) }
            throw StoreError.saveFailed
        }
        presets = draft
        try? removeFile(at: from)   // no record names it any more
    }

    /// PRE-018-R7 (MED-013 pattern): writes a waiting or playable preset's stored copy back from bytes
    /// whose size and SHA-256 equal the record's. The record is not changed. Throws `saveFailed` for any
    /// other bytes, a quarantined preset, or a failed write.
    public func restoreContents(_ id: String, contents: Data) throws {
        try requireWritable()
        guard let preset = preset(id: id) else { throw StoreError.unknownPreset }
        let bytes = [UInt8](contents)
        guard preset.state != .quarantined, bytes.count == preset.byteCount,
              ContentHash.sha256Hex(bytes) == preset.sha256 else { throw StoreError.saveFailed }
        let url = fileURL(preset)
        do {
            try createDirectory(url.deletingLastPathComponent())
            try writeFile(contents, to: url)
        } catch {
            throw StoreError.saveFailed
        }
    }

    /// PRE-018-D3: the stored copy's bytes when its size matches the record (read at most `byteCount`
    /// bytes plus one); nil when absent, unreadable or of another size. Never follows the record outside
    /// the directory (the path is built from the validated hash).
    func storedBytes(of preset: UserPreset) -> [UInt8]? {
        let url = fileURL(preset)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size == preset.byteCount,
              size <= PresetImportLimits.maxFileBytes, let data = try? Data(contentsOf: url) else { return nil }
        return data.count == preset.byteCount ? [UInt8](data) : nil
    }

    /// Removes the record, then its copy.
    public func remove(_ id: String) throws {
        try requireWritable()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw StoreError.unknownPreset }
        let preset = presets[index]
        var draft = presets
        draft.remove(at: index)
        guard save(draft) else { throw StoreError.saveFailed }
        presets = draft
        let url = fileURL(preset)
        try? removeFile(at: url)
        removeIfEmpty(url.deletingLastPathComponent())
    }

    /// "<64 lowercase hex>.milk": the only names the store gives texts.
    static func isStoredFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".milk") else { return false }
        let hash = name.dropLast(5)
        return hash.count == 64 && hash.allSatisfy { (c: Character) -> Bool in ("0"..."9").contains(c) || ("a"..."f").contains(c) }
    }

    // MARK: - Trial records (R17, R18)

    /// Durably notes that `presetID` is being tried or first shown. Throws when it cannot be
    /// written: the caller must then not start.
    public func writeRecord(_ phase: Phase, presetID: String, candidateSHA256: String? = nil) throws {
        try requireWritable()
        do {
            let data = try JSONEncoder().encode(TrialRecord(presetID: presetID, phase: phase, candidateSHA256: candidateSHA256))
            try createDirectory(directory)
            try writeFile(data, to: recordURL(phase))
        } catch {
            throw StoreError.saveFailed
        }
    }

    public func clearRecord(_ phase: Phase) {
        guard FileManager.default.fileExists(atPath: recordURL(phase).path) else { return }
        try? removeFile(at: recordURL(phase))
        removeIfEmpty(directory)
    }

    public func hasRecord(_ phase: Phase) -> Bool {
        FileManager.default.fileExists(atPath: recordURL(phase).path)
    }

    /// Records left by a launch that ended inside a trial or a proving period. A record that
    /// cannot be read names nothing and is removed. The readable ones stay on disk until the
    /// caller has dealt with them and calls `clearRecord`.
    public func leftoverRecords() -> [LeftoverRecord] {
        guard availability == .available else { return [] }
        var found: [LeftoverRecord] = []
        for phase in Phase.allCases {
            let url = recordURL(phase)
            guard let data = try? Data(contentsOf: url) else { continue }
            guard data.count <= 4_096, let record = try? JSONDecoder().decode(TrialRecord.self, from: data),
                  record.schemaVersion == 1, record.phase == phase, record.presetID.hasPrefix(UserPreset.idPrefix) else {
                clearRecord(phase)
                continue
            }
            found.append(LeftoverRecord(phase: phase, presetID: record.presetID, candidateSHA256: record.candidateSHA256))
        }
        return found
    }

    // MARK: - Files

    private func requireWritable() throws {
        if case .newerFormat = availability { throw StoreError.newerFormat }
        if savingBlocked { throw StoreError.saveFailed }
    }

    /// Built from the validated hash only.
    private func fileURL(_ preset: UserPreset) -> URL {
        directory.appendingPathComponent(preset.state == .quarantined ? Self.quarantineFolder : Self.filesFolder, isDirectory: true)
            .appendingPathComponent(preset.fileName)
    }

    private func recordURL(_ phase: Phase) -> URL { directory.appendingPathComponent(phase.fileName) }

    private func removeIfEmpty(_ folder: URL) {
        if let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path), items.isEmpty { try? removeFile(at: folder) }
    }

    private func save(_ list: [UserPreset]) -> Bool {
        do {
            let data = try UserPresetsFile(presets: list).encode()
            guard data.count <= PresetImportLimits.maxIndexBytes else { return false }
            try createDirectory(directory)
            try perform(.write, indexURL) { try write(data, indexURL) }
        } catch {
            return false
        }
        if let backup = migrationBackup {
            try? removeFile(at: backup)
            migrationBackup = nil
        }
        return true
    }

    /// Keeps the original until the migrated record is on disk (the PRE-007 rule).
    private func saveMigrated(from version: Int) {
        let backup = directory.appendingPathComponent("index.v\(version).backup.json")
        if FileManager.default.fileExists(atPath: backup.path) { try? removeFile(at: backup) }
        do {
            try perform(.copy, backup, also: indexURL) { try FileManager.default.copyItem(at: indexURL, to: backup) }
        } catch {
            savingBlocked = true
            return
        }
        migrationBackup = backup
        _ = save(presets)
    }

    // MARK: - The path guard (PRE-015-R19)

    /// `url` as an absolute path with `.`, `..` and symbolic links of its existing part resolved.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        let files = FileManager.default
        while !files.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var path = existing.resolvingSymlinksInPath().standardizedFileURL.path
        for component in tail { path = (path as NSString).appendingPathComponent(component) }
        return (path as NSString).standardizingPath
    }

    /// True when `url` is the directory or inside it.
    func contains(_ url: URL) -> Bool {
        let root = Self.canonicalPath(directory)
        let path = Self.canonicalPath(url)
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// The one place a file operation happens. Refuses (`saveFailed`, nothing performed) when a
    /// path is outside the directory.
    private func perform(_ operation: FileOperation, _ url: URL, also other: URL? = nil, _ body: () throws -> Void) throws {
        guard contains(url), other.map(contains) ?? true else { throw StoreError.saveFailed }
        fileOperationObserver?(operation, url)
        if let other { fileOperationObserver?(operation, other) }
        try fileOperationFault?(operation, url)
        try body()
    }

    func writeFile(_ data: Data, to url: URL) throws {
        try perform(.write, url) { try data.write(to: url, options: .atomic) }
    }

    func removeFile(at url: URL) throws {
        try perform(.remove, url) { try FileManager.default.removeItem(at: url) }
    }

    private func moveFile(_ from: URL, to: URL) throws {
        try perform(.move, to, also: from) { try FileManager.default.moveItem(at: from, to: to) }
    }

    private func createDirectory(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try perform(.createDirectory, url) { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }
}
