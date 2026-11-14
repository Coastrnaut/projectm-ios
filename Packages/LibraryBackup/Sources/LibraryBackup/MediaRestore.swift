// MediaRestore.swift — FILE-006 contract B5 (research FILE-006-D6; FILE-006-R8): media back from a folder
// backup.
//
// * Stage (when the user picks the folder): the folder's manifest must be usable; every asset of a known
//   kind is copied into `Application Support/MediaRestore/staged/` while hashed, and its size and SHA-256
//   must equal the entry (all files are verified, none sampled). Any mismatch refuses the whole restore
//   and removes the staging. `request.json` is written last.
// * Install (next launch, after FILE-005's restore and before FILE-008's reconcile, so no store is
//   loaded): a photo or video is written as a legacy `<UUID>.<ext>` file only when its identifier does
//   not resolve on the device (the device's file is never replaced; the launch migration registers the
//   new one); imported audio (assets, then the index) only when the device has no audio index. Each
//   step is repeatable, so an interrupted install simply runs again; the request goes last.
// Nothing here uses the network; the folder is only read.
import Foundation
import LocalPortability

public enum MediaRestoreError: Error, Sendable, Equatable {
    /// No usable manifest in the folder.
    case noManifest
    /// A copy is missing, has another size or another hash (the asset's name).
    case unverifiable(String)
    case stagingFailed

    public var message: String {
        switch self {
        case .noManifest: "This folder does not hold a projectM-iOS backup that can be read."
        case let .unverifiable(name): "\(name) in the backup is missing or damaged. Nothing was restored."
        case .stagingFailed: "The media could not be copied from the folder. Nothing was restored."
        }
    }
}

public struct MediaRestoreSummary: Sendable, Equatable {
    public var assets: Int
    public var bytes: Int64
    /// Entries of kinds or names this version does not restore.
    public var skipped: Int
}

public struct MediaRestoreResult: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var installed: Int
    public var alreadyHere: Int
    public var skipped: Int

    public init(installed: Int, alreadyHere: Int, skipped: Int) {
        schemaVersion = 1
        self.installed = installed
        self.alreadyHere = alreadyHere
        self.skipped = skipped
    }

    public var message: String {
        var text = "Media restored: " + String(installed) + " added, " + String(alreadyHere) + " already on this device."
        if skipped > 0 { text += " " + String(skipped) + " not added (imported audio is already on this device, or the backup is newer)." }
        return text
    }
}

struct MediaRestoreRequest: Codable, Equatable {
    var schemaVersion: Int
    var assets: [BackupAssetEntry]
}

public struct MediaRestoreRequestStore: Sendable {
    public static let folderName = "MediaRestore"
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var folder: URL { root.appendingPathComponent(Self.folderName, isDirectory: true) }
    var staged: URL { folder.appendingPathComponent("staged", isDirectory: true) }
    var requestFile: URL { folder.appendingPathComponent("request.json", isDirectory: false) }
    var resultFile: URL { folder.appendingPathComponent("last-result.json", isDirectory: false) }

    /// A readable request of this version, or nil.
    var request: MediaRestoreRequest? {
        guard let data = try? Data(contentsOf: requestFile), data.count <= BackupFolderManifest.maxBytes,
              let request = try? JSONDecoder().decode(MediaRestoreRequest.self, from: data), request.schemaVersion == 1 else { return nil }
        return request
    }

    public var isPending: Bool { request != nil }

    /// Removes the request and the staged copies (the last result stays).
    public func cancel() {
        try? FileManager.default.removeItem(at: requestFile)
        try? FileManager.default.removeItem(at: staged)
    }

    /// The launch-time result, once.
    public func takeResult() -> MediaRestoreResult? {
        guard let data = try? Data(contentsOf: resultFile) else { return nil }
        try? FileManager.default.removeItem(at: resultFile)
        guard let result = try? JSONDecoder().decode(MediaRestoreResult.self, from: data), result.schemaVersion == 1 else { return nil }
        return result
    }
}

public struct MediaRestoreStager: Sendable {
    public let access: any BackupFileAccess

    public init(access: any BackupFileAccess = LocalBackupFileAccess()) {
        self.access = access
    }

    /// Verifies and stages the media of the backup in (or under) `picked` for the next launch.
    public func stage(from picked: URL, root: URL) throws(MediaRestoreError) -> MediaRestoreSummary {
        let folder = BackupFolderLayout.backupFolder(in: picked)
        guard let manifest = BackupFolderManifest.read(folder: folder) else { throw .noManifest }
        let store = MediaRestoreRequestStore(root: root)
        store.cancel()
        do {
            try FileManager.default.createDirectory(at: store.staged, withIntermediateDirectories: true)
        } catch {
            throw .stagingFailed
        }
        var summary = MediaRestoreSummary(assets: 0, bytes: 0, skipped: 0)
        var kept: [BackupAssetEntry] = []
        var done: Set<String> = []
        do throws(MediaRestoreError) {
            for entry in manifest.assets {
                guard MediaRestoreInstaller.isRestorable(entry) else {
                    summary.skipped += 1
                    continue
                }
                if !done.contains(entry.location) {
                    try verifyAndStage(entry, from: folder, into: store.staged)
                    done.insert(entry.location)
                    summary.bytes += entry.byteCount
                }
                kept.append(entry)
                summary.assets += 1
            }
            let data: Data
            do {
                data = try JSONEncoder().encode(MediaRestoreRequest(schemaVersion: 1, assets: kept))
                try data.write(to: store.requestFile, options: .atomic)
            } catch {
                throw MediaRestoreError.stagingFailed
            }
        } catch {
            store.cancel()
            throw error
        }
        return summary
    }

    private func verifyAndStage(_ entry: BackupAssetEntry, from folder: URL, into staged: URL) throws(MediaRestoreError) {
        guard let sha256 = entry.sha256 else { throw .unverifiable(entry.name) }
        let source = folder.appendingPathComponent(entry.location, isDirectory: false)
        guard access.status(of: source, includingDate: false)?.byteCount == entry.byteCount else { throw .unverifiable(entry.name) }
        let target = staged.appendingPathComponent(URL(fileURLWithPath: entry.location).lastPathComponent, isDirectory: false)
        let partial = staged.appendingPathComponent(BackupFolderLayout.partialPrefix + UUID().uuidString, isDirectory: false)
        let digest: BackupDigest
        do {
            digest = try access.copy(from: source, to: partial)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw .stagingFailed
        }
        guard digest.sha256 == sha256, digest.byteCount == entry.byteCount else {
            try? FileManager.default.removeItem(at: partial)
            throw .unverifiable(entry.name)
        }
        do {
            try FileManager.default.moveItem(at: partial, to: target)
        } catch {
            throw .stagingFailed
        }
    }
}

public enum MediaRestoreInstaller {
    /// A kind this version restores, with a name that kind's store accepts.
    static func isRestorable(_ entry: BackupAssetEntry) -> Bool {
        switch entry.kind {
        case BackupAssetKind.photo: LibraryBackupFormat.isPhotoName(entry.name)
        case BackupAssetKind.video: legacyID(entry.name, extensions: LibraryErasePolicy.videoExtensions) != nil
        case BackupAssetKind.audio: BackupFolderLayout.isContentName(entry.name)
        case BackupAssetKind.audioIndex: entry.name == MediaBackupInventory.audioIndexName
        default: false
        }
    }

    static func legacyID(_ name: String, extensions: [String]) -> UUID? {
        ContentAddressedMediaFolder(directory: URL(fileURLWithPath: "/"), extensions: extensions).legacyID(name)
    }

    /// Installs the staged request (see the file header). Returns nil when nothing was pending.
    static func install(_ request: MediaRestoreRequest, store: MediaRestoreRequestStore) -> MediaRestoreResult {
        var result = MediaRestoreResult(installed: 0, alreadyHere: 0, skipped: 0)
        let root = store.root
        func staged(_ entry: BackupAssetEntry) -> URL {
            store.staged.appendingPathComponent(URL(fileURLWithPath: entry.location).lastPathComponent, isDirectory: false)
        }
        let photos = ContentAddressedMediaFolder(directory: MediaBackupInventory.photosFolder(root), extensions: LibraryErasePolicy.photoExtensions)
        let videos = ContentAddressedMediaFolder(directory: MediaBackupInventory.videosFolder(root), extensions: LibraryErasePolicy.videoExtensions)
        for entry in request.assets {
            let folder: ContentAddressedMediaFolder
            switch entry.kind {
            case BackupAssetKind.photo: folder = photos
            case BackupAssetKind.video: folder = videos
            default: continue
            }
            guard let id = folder.legacyID(entry.name) else {
                result.skipped += 1
                continue
            }
            if folder.resolve(id) != nil {
                result.alreadyHere += 1
            } else if place(staged(entry), at: folder.payloadURL(entry.name)) {
                result.installed += 1
            } else {
                result.skipped += 1
            }
        }
        installAudio(request.assets.filter { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.audio || e.kind == BackupAssetKind.audioIndex },
                     root: root, staged: staged, result: &result)
        return result
    }

    private static func installAudio(_ entries: [BackupAssetEntry], root: URL, staged: (BackupAssetEntry) -> URL, result: inout MediaRestoreResult) {
        guard let index = entries.first(where: { (e: BackupAssetEntry) -> Bool in e.kind == BackupAssetKind.audioIndex }) else {
            result.skipped += entries.count   // assets without their index cannot be listed by the audio library
            return
        }
        let audio = MediaBackupInventory.audioFolder(root)
        let indexURL = audio.appendingPathComponent(MediaBackupInventory.audioIndexName, isDirectory: false)
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let same: Bool = (try? Data(contentsOf: indexURL)) == (try? Data(contentsOf: staged(index)))
            if same { result.alreadyHere += entries.count } else { result.skipped += entries.count }
            return
        }
        let assets = audio.appendingPathComponent(MediaBackupInventory.audioAssetsFolderName, isDirectory: true)
        for entry in entries where entry.kind == BackupAssetKind.audio {
            let target = assets.appendingPathComponent(entry.name, isDirectory: false)
            if FileManager.default.fileExists(atPath: target.path) {
                result.alreadyHere += 1
            } else if place(staged(entry), at: target) {
                result.installed += 1
            } else {
                result.skipped += 1
            }
        }
        if place(staged(index), at: indexURL) { result.installed += 1 } else { result.skipped += 1 }   // the index last
    }

    /// Copies under a temporary name in the target's folder, then renames (atomic on one volume).
    static func place(_ source: URL, at target: URL) -> Bool {
        let files = FileManager.default
        let folder = target.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(ContentAddressedMediaFolder.incomingPrefix + UUID().uuidString + "." + target.pathExtension,
                                                      isDirectory: false)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            try files.copyItem(at: source, to: temporary)
            try files.moveItem(at: temporary, to: target)
            return true
        } catch {
            try? files.removeItem(at: temporary)
            return false
        }
    }
}

public enum MediaRestoreLaunch {
    /// Installs a pending media restore (if any) and records its result. Repeatable.
    @discardableResult
    public static func run(root: URL) -> MediaRestoreResult? {
        let store = MediaRestoreRequestStore(root: root)
        guard FileManager.default.fileExists(atPath: store.folder.path) else { return nil }
        guard let request = store.request else {
            store.cancel()   // a newer app's or a damaged request: ignored and removed; staging leftovers too
            return nil
        }
        let result = MediaRestoreInstaller.install(request, store: store)
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: store.resultFile, options: .atomic) }
        store.cancel()
        return result
    }
}
