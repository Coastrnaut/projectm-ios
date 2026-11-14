// FolderBackupWriter.swift — FILE-006 contract B4 (research FILE-006-D2-D4; FILE-006-R3-R7): the
// incremental folder backup.
//
// For each asset, against the previous manifest in the folder:
// * unchanged — same key, same size, same content address (name-derived) or, for a file without one,
//   the same modification date; and the copy that entry names still has that size. Neither read nor
//   copied: the previous entry is kept.
// * content-addressed with a copy of that name already trusted (named by the previous manifest, or made
//   in this run) — the copy is reused without reading the source.
// * otherwise — copied once into `media/.partial-<UUID>` while hashed, then renamed `media/<sha256>.<ext>`.
// No usable previous manifest (missing, damaged, newer): a full backup, nothing in the folder trusted.
// Order: copies → archive (atomic) → manifest (atomic) → prune (only `<sha256>.<ext>` and `.partial-*`
// names in our own `media/` that the new manifest does not name). The previous manifest therefore always
// names files that exist; an interruption leaves at worst unnamed leftovers, collected next time.
import Foundation
import LocalPortability

public enum FolderBackupStep: String, Sendable, CaseIterable {
    case copy, writeArchive, writeManifest, prune
}

public enum FolderBackupError: Error, Sendable, Equatable {
    case folderUnavailable
    case copyFailed(String)
    case writeFailed

    public var message: String {
        switch self {
        case .folderUnavailable: "The folder could not be written. Choose another folder."
        case let .copyFailed(name): "The backup to the folder did not finish: \(name) could not be copied. The previous backup there is unchanged."
        case .writeFailed: "The backup to the folder did not finish. The previous backup there is unchanged."
        }
    }
}

public struct FolderBackupReport: Sendable, Equatable {
    /// Files copied in this run.
    public var copied: Int
    /// Assets whose copy was already in the backup (not read, not copied).
    public var unchanged: Int
    /// Copies pruned because no asset names them any more.
    public var removed: Int
    public var bytesCopied: Int64
    /// No usable previous manifest: everything was copied.
    public var fullBackup: Bool
    public var manifest: BackupFolderManifest
}

public struct FolderBackupWriter: Sendable {
    public let access: any BackupFileAccess
    /// Tests only: a thrown error aborts the backup at that step (the name is the asset's or the file's).
    public var fault: (@Sendable (FolderBackupStep, String) throws -> Void)?

    public init(access: any BackupFileAccess = LocalBackupFileAccess(), fault: (@Sendable (FolderBackupStep, String) throws -> Void)? = nil) {
        self.access = access
        self.fault = fault
    }

    /// Backs up `assets` (and the FILE-005 `archive`, when given) into `folder` (the resolved backup folder).
    public func write(archive: Data?, assets: [BackupAsset], to folder: URL, appVersion: String,
                      createdAt: Date) throws(FolderBackupError) -> FolderBackupReport {
        let media = folder.appendingPathComponent(BackupFolderLayout.mediaFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        } catch {
            throw .folderUnavailable
        }
        let previous = BackupFolderManifest.read(folder: folder)
        var run = Run(previous: previous)
        var entries: [BackupAssetEntry] = []
        for asset in assets {
            if let entry = try backUp(asset, folder: folder, media: media, run: &run) { entries.append(entry) }
        }
        var library: BackupArchiveRecord?
        if let archive {
            library = BackupArchiveRecord(path: BackupFolderLayout.archiveName, byteCount: Int64(archive.count), sha256: PortableSHA256.hex(archive))
            do {
                try fault?(.writeArchive, BackupFolderLayout.archiveName)
                try archive.write(to: folder.appendingPathComponent(BackupFolderLayout.archiveName, isDirectory: false), options: .atomic)
            } catch {
                throw .writeFailed
            }
        }
        let manifest = BackupFolderManifest(appVersion: appVersion, createdAt: LibraryBackupWriter.iso8601(createdAt), library: library,
                                            assets: entries)
        do {
            try fault?(.writeManifest, BackupFolderLayout.manifestName)
            try manifest.encoded().write(to: folder.appendingPathComponent(BackupFolderLayout.manifestName, isDirectory: false), options: .atomic)
        } catch {
            throw .writeFailed
        }
        let removed = prune(media, keeping: Set(manifest.assets.map { (entry: BackupAssetEntry) -> String in entry.location }))
        return FolderBackupReport(copied: run.copied, unchanged: run.unchanged, removed: removed, bytesCopied: run.bytesCopied,
                                  fullBackup: previous == nil, manifest: manifest)
    }

    /// The state of one backup run.
    private struct Run {
        let full: Bool
        let previous: [String: BackupAssetEntry]
        /// Locations named by the previous manifest (copies hashed when they were written).
        let trusted: Set<String>
        /// Locations written in this run.
        var written: Set<String> = []
        var copied = 0
        var unchanged = 0
        var bytesCopied: Int64 = 0

        init(previous manifest: BackupFolderManifest?) {
            full = manifest == nil
            let entries: [BackupAssetEntry] = manifest?.assets ?? []
            var byKey: [String: BackupAssetEntry] = [:]
            for entry in entries { byKey[entry.key] = entry }
            previous = byKey
            trusted = Set(entries.map { (entry: BackupAssetEntry) -> String in entry.location })
        }
    }

    private func size(_ folder: URL, _ location: String) -> Int64? {
        access.status(of: folder.appendingPathComponent(location, isDirectory: false), includingDate: false)?.byteCount
    }

    private func backUp(_ asset: BackupAsset, folder: URL, media: URL, run: inout Run) throws(FolderBackupError) -> BackupAssetEntry? {
        let dated: Bool = asset.contentAddress == nil
        guard let status = access.status(of: asset.url, includingDate: dated) else { return nil }   // gone since the listing
        if !run.full, let entry = run.previous[asset.key], isUnchanged(entry, asset: asset, status: status), size(folder, entry.location) == entry.byteCount {
            run.unchanged += 1
            return entry
        }
        if let address = asset.contentAddress {
            let location = BackupFolderLayout.location(sha256: address, fileExtension: asset.fileExtension)
            let reusable: Bool = run.written.contains(location) || (!run.full && run.trusted.contains(location))
            if reusable, size(folder, location) == status.byteCount {
                run.unchanged += 1
                return BackupAssetEntry(kind: asset.kind, name: asset.name, byteCount: status.byteCount, modified: nil, sha256: address,
                                        location: location)
            }
        }
        let digest = try copy(asset, folder: folder, media: media)
        let location = BackupFolderLayout.location(sha256: digest.sha256, fileExtension: asset.fileExtension)
        run.written.insert(location)
        run.copied += 1
        run.bytesCopied += digest.byteCount
        return BackupAssetEntry(kind: asset.kind, name: asset.name, byteCount: digest.byteCount, modified: dated ? status.modified : nil,
                                sha256: digest.sha256, location: location)
    }

    private func isUnchanged(_ entry: BackupAssetEntry, asset: BackupAsset, status: BackupFileStatus) -> Bool {
        guard let hash = entry.sha256, entry.byteCount == status.byteCount else { return false }
        if let address = asset.contentAddress { return hash == address }
        guard let before = entry.modified, let now = status.modified else { return false }
        return before == now
    }

    /// One streaming read into a temporary copy, then the rename to its content name.
    private func copy(_ asset: BackupAsset, folder: URL, media: URL) throws(FolderBackupError) -> BackupDigest {
        let files = FileManager.default
        let partial = media.appendingPathComponent(BackupFolderLayout.partialPrefix + UUID().uuidString, isDirectory: false)
        do {
            try fault?(.copy, asset.name)
            let digest = try access.copy(from: asset.url, to: partial)
            let target = folder.appendingPathComponent(BackupFolderLayout.location(sha256: digest.sha256, fileExtension: asset.fileExtension),
                                                       isDirectory: false)
            try? files.removeItem(at: target)
            try files.moveItem(at: partial, to: target)
            return digest
        } catch {
            try? files.removeItem(at: partial)
            throw .copyFailed(asset.name)
        }
    }

    /// Removes our own unnamed copies and leftovers; a failure stops pruning (the next backup retries).
    private func prune(_ media: URL, keeping: Set<String>) -> Int {
        let files = FileManager.default
        var removed = 0
        let names = ((try? files.contentsOfDirectory(atPath: media.path)) ?? []).sorted()
        for name in names {
            let location = BackupFolderLayout.mediaFolderName + "/" + name
            let partial: Bool = name.hasPrefix(BackupFolderLayout.partialPrefix)
            guard partial || (BackupFolderLayout.isContentName(name) && !keeping.contains(location)) else { continue }
            do {
                try fault?(.prune, name)
                try files.removeItem(at: media.appendingPathComponent(name, isDirectory: false))
                if !partial { removed += 1 }
            } catch {
                break
            }
        }
        return removed
    }
}
