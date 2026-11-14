// MediaBackupInventory.swift — FILE-006 contract B3 (data-model "BackupAsset"): the media a folder backup
// holds, read from directory listings and FILE-008's registries only (no media bytes).
//
// * photo: `Photos/` logical files (`<UUID>.png|jpg`), legacy copies and registered payloads alike.
// * video: `Videos/` logical files (`<UUID>.mov`).
// * audio: `AudioLibrary/assets/<sha256>[.<ext>]` (AUD-001, content-addressed).
// * audio-index: `AudioLibrary/index.json` (the audio library's record; small, tracked by size and date).
// A stored file named `<sha256>.<ext>` carries its content address, so its identity needs no reading.
import Foundation
import LocalPortability

public struct BackupAsset: Sendable, Equatable {
    public var kind: String
    public var name: String
    /// The stored file.
    public var url: URL
    /// The SHA-256 the stored file's name carries (FILE-008 payload, AUD-001 asset); nil otherwise.
    public var contentAddress: String?

    public init(kind: String, name: String, url: URL, contentAddress: String?) {
        self.kind = kind
        self.name = name
        self.url = url
        self.contentAddress = contentAddress
    }

    public var key: String { kind + "/" + name }

    /// The lowercase extension of the logical name ("" when none).
    public var fileExtension: String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        let ext = name[name.index(after: dot)...].lowercased()
        return BackupFolderLayout.isExtension(ext) ? ext : ""
    }
}

public enum MediaBackupInventory {
    public static let audioAssetsFolderName = "assets"
    public static let audioIndexName = "index.json"

    public static func photosFolder(_ root: URL) -> URL { LibraryFolders(root: root).url(.photos) }
    public static func videosFolder(_ root: URL) -> URL { root.appendingPathComponent(LibraryErasePolicy.videosFolderName, isDirectory: true) }
    public static func audioFolder(_ root: URL) -> URL { root.appendingPathComponent(LibraryErasePolicy.audioFolderName, isDirectory: true) }

    /// Every asset under the library root, sorted by kind and name.
    public static func assets(root: URL) -> [BackupAsset] {
        var assets: [BackupAsset] = []
        assets += media(ContentAddressedMediaFolder(directory: photosFolder(root), extensions: LibraryErasePolicy.photoExtensions),
                        kind: BackupAssetKind.photo)
        assets += media(ContentAddressedMediaFolder(directory: videosFolder(root), extensions: LibraryErasePolicy.videoExtensions),
                        kind: BackupAssetKind.video)
        let audio = audioFolder(root)
        let assetsFolder = audio.appendingPathComponent(audioAssetsFolderName, isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: assetsFolder.path)) ?? []).sorted()
        for name in names {
            guard let address = BackupFolderLayout.contentAddress(of: name) else { continue }
            assets.append(BackupAsset(kind: BackupAssetKind.audio, name: name, url: assetsFolder.appendingPathComponent(name, isDirectory: false),
                                      contentAddress: address))
        }
        let index = audio.appendingPathComponent(audioIndexName, isDirectory: false)
        if FileManager.default.fileExists(atPath: index.path) {
            assets.append(BackupAsset(kind: BackupAssetKind.audioIndex, name: audioIndexName, url: index, contentAddress: nil))
        }
        return assets.sorted { (a: BackupAsset, b: BackupAsset) -> Bool in a.key < b.key }
    }

    private static func media(_ folder: ContentAddressedMediaFolder, kind: String) -> [BackupAsset] {
        folder.logicalFiles().map { (entry: (key: String, value: URL)) -> BackupAsset in
            let stored = entry.value.lastPathComponent
            let address: String? = folder.isPayloadName(stored) ? BackupFolderLayout.contentAddress(of: stored) : nil
            return BackupAsset(kind: kind, name: entry.key, url: entry.value, contentAddress: address)
        }
    }
}
