// UserPresetStore+History.swift — roadmap PRE-017 (specs/250-pre-017-preset-restore-points; R1-R4, R7;
// research D1-D5): the store's earlier versions of edited presets.
//
// * `versions/<sha256>.milk` holds earlier texts, content-addressed and separate from `files/`; `history.json`
//   lists, per preset, which texts are versions of it. A version text is deleted only when no version of any
//   preset names it (reference counting), and only `<64 hex>.milk` names inside `versions/` are ever deleted.
// * Every file operation goes through the store's path guard (`perform`).
// * A newer list is never written (edits save without versions); an unreadable one is set aside as
//   `history.unreadable.json` and nothing in `versions/` is collected while that file exists.
import Foundation

extension UserPresetStore {
    static let versionsFolder = "versions"

    /// What `keepVersion` changed, so it can be undone or finished.
    struct KeptVersion {
        var previous: UserPresetHistoryFile
        var current: UserPresetHistoryFile
        /// The version text this call wrote (nil when the file was already there).
        var addedFile: URL?
    }

    var historyURL: URL { directoryURL.appendingPathComponent(UserPresetHistoryFile.fileName) }
    private var historyAsideURL: URL { directoryURL.appendingPathComponent(UserPresetHistoryFile.unreadableFileName) }
    private var versionsURL: URL { directoryURL.appendingPathComponent(Self.versionsFolder, isDirectory: true) }

    func versionURL(_ sha256: String) -> URL { versionsURL.appendingPathComponent(sha256 + ".milk") }

    // MARK: - Reading

    /// Newest first.
    public func versions(of id: String) -> [UserPresetVersion] {
        guard versionsAvailability == .available else { return [] }
        return history.versions(of: id).reversed()
    }

    /// A version's text when it is listed for `id` and its file has the listed size and SHA-256.
    func versionBytes(of id: String, sha256: String) -> [UInt8]? {
        guard versionsAvailability == .available,
              let version = history.versions(of: id).first(where: { (v: UserPresetVersion) -> Bool in v.sha256 == sha256 }) else { return nil }
        let url = versionURL(version.sha256)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size == version.byteCount,
              let data = try? Data(contentsOf: url), data.count == version.byteCount else { return nil }
        let bytes = [UInt8](data)
        return ContentHash.sha256Hex(bytes) == version.sha256 ? bytes : nil
    }

    // MARK: - Loading (PRE-017-R3, R7)

    /// At init, once the record is read. Never writes a newer list; sets an unreadable one aside.
    func loadHistory() {
        let files = FileManager.default
        if files.fileExists(atPath: historyURL.path) {
            do {
                history = try UserPresetHistoryFile.decode(Data(contentsOf: historyURL))
            } catch UserPresetHistoryFile.ReadError.newerVersion {
                versionsAvailability = .newerFormat
                return
            } catch {
                try? removeFile(at: historyAsideURL)
                if (try? moveFile(historyURL, to: historyAsideURL)) == nil { historyBlocked = true }
                history = UserPresetHistoryFile()
                return
            }
        }
        // Only a record read as it is can say which presets exist.
        guard indexTrusted, !files.fileExists(atPath: historyAsideURL.path) else { return }
        let known: Set<String> = Set(presets.map(\.id))
        let cleaned = history.filtered { (id: String, version: UserPresetVersion) -> Bool in
            known.contains(id) && files.fileExists(atPath: versionURL(version.sha256).path)
        }
        if cleaned != history, saveHistory(cleaned) { history = cleaned }
        collectUnnamedVersions(keeping: history.namedHashes)
    }

    // MARK: - Changes

    /// Writes the list atomically (removes the file when it is empty). False on failure; nothing in memory changes.
    func saveHistory(_ file: UserPresetHistoryFile) -> Bool {
        guard versionsAvailability == .available, !historyBlocked else { return false }
        do {
            if file.presets.isEmpty {
                if FileManager.default.fileExists(atPath: historyURL.path) { try removeFile(at: historyURL) }
                return true
            }
            let data = try file.encode()
            guard data.count <= UserPresetHistoryFile.maxBytes else { return false }
            try createDirectory(directoryURL)
            try writeFile(data, to: historyURL)
            return true
        } catch {
            return false
        }
    }

    /// Research D3, steps 2-3: copies `old`'s intact text into `versions/` and saves the list with it.
    /// Nil (nothing kept, no error) when versions are unavailable or the old text is missing or damaged;
    /// throws when an intact text could not be kept (the caller refuses the change).
    func keepVersion(of old: UserPreset, replacedAt: Date) throws -> KeptVersion? {
        guard versionsAvailability == .available, !historyBlocked,
              let bytes = storedBytes(of: old), ContentHash.sha256Hex(bytes) == old.sha256 else { return nil }
        let version = UserPresetVersion(sha256: old.sha256, blobHash: old.blobHash, byteCount: old.byteCount,
                                        replacedAt: replacedAt, name: old.name)
        let url = versionURL(old.sha256)
        var added: URL?
        if !FileManager.default.fileExists(atPath: url.path) {
            try createDirectory(versionsURL)
            try writeFile(Data(bytes), to: url)
            added = url
        }
        let current = history.adding(version, to: old.id, limits: historyLimits)
        guard saveHistory(current) else {
            if let added { try? removeFile(at: added) }
            removeIfEmpty(versionsURL)
            throw StoreError.saveFailed
        }
        let kept = KeptVersion(previous: history, current: current, addedFile: added)
        history = current
        return kept
    }

    /// The record could not be saved: the list and the version text go back to how they were.
    func undoKeptVersion(_ kept: KeptVersion) {
        if saveHistory(kept.previous) { history = kept.previous }
        if let added = kept.addedFile { try? removeFile(at: added) }
        removeIfEmpty(versionsURL)
    }

    /// The record is saved: version texts pruning left unnamed are deleted.
    func finishKeptVersion(_ kept: KeptVersion) {
        let dropped = kept.previous.namedHashes.subtracting(kept.current.namedHashes)
        deleteVersionTexts(dropped)
    }

    /// PRE-017-R7: after a preset is removed, its list entry, then each of its texts no other version names.
    func removeVersions(of id: String) {
        guard versionsAvailability == .available, !history.versions(of: id).isEmpty else { return }
        let draft = history.removing(id)
        guard saveHistory(draft) else { return }   // the entry is dropped at the next load
        let dropped = history.namedHashes.subtracting(draft.namedHashes)
        history = draft
        deleteVersionTexts(dropped)
    }

    private func deleteVersionTexts(_ hashes: Set<String>) {
        let named = history.namedHashes
        for hash in hashes where !named.contains(hash) {
            let url = versionURL(hash)
            guard Self.isStoredFileName(url.lastPathComponent), FileManager.default.fileExists(atPath: url.path) else { continue }
            try? removeFile(at: url)
        }
        removeIfEmpty(versionsURL)
    }

    /// Deletes `<sha256>.milk` files in `versions/` that no version names (left by an interrupted save).
    private func collectUnnamedVersions(keeping named: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: versionsURL.path) else { return }
        for name in names where Self.isStoredFileName(name) && !named.contains(String(name.dropLast(5))) {
            try? removeFile(at: versionsURL.appendingPathComponent(name))
        }
        removeIfEmpty(versionsURL)
    }
}
