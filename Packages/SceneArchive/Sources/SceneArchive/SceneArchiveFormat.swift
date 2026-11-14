// SceneArchiveFormat.swift — names and limits of the scene archive, format version 1
// (FILE-001-R1, R2, R6, R14; research FILE-001-D4, D8; contract §1-3).
import LocalPortability

public enum SceneArchiveFormat {
    /// The PortableArchive format name in `manifest.json`.
    public static let formatName = "projectm-ios.scene-archive"
    public static let currentVersion = 1
    public static let scenePath = "scene.json"
    public static let assetFolder = "assets/"
    /// The file extension and the type identifier the screen row (SCN-014) declares.
    public static let fileExtension = "pmscene"
    public static let typeIdentifier = "org.projectmios.scene-archive"

    /// The manifest's versioned constraints (FILE-007-R5; contract C2 of
    /// specs/068-file-007-document-schema-validator): version 1 only; depth 8 (the largest valid
    /// manifest has 3), strings up to 4,096 bytes (paths are at most 255), numbers up to 32
    /// characters, 256 elements per list or object (3 files at most), no duplicate keys. The byte
    /// limit is the reader's `maxManifestBytes` (64 KiB standard).
    public static let manifestSchema = DocumentSchema(
        name: formatName, oldestReadableVersion: 1, currentVersion: currentVersion,
        limits: JSONLimits(maxBytes: SceneArchiveLimits.standard.maxManifestBytes, maxDepth: 8, maxStringBytes: 4_096,
                           maxNumberBytes: 32, maxElements: 256))

    /// Allowed extensions per asset type, in the order the writer prefers.
    public static func allowedExtensions(for type: SceneArchiveAssetType) -> [String] {
        switch type {
        case .photo: ["png", "jpg"]
        case .video: ["mov"]
        case .logo: ["png"]   // MED-010-R11: always PNG (alpha)
        }
    }

    /// `assets/<key>.<ext>`: keys are SCN-001 asset keys (ASCII letters and digits), so the path
    /// cannot leave the folder.
    public static func assetPath(key: String, fileExtension: String) -> String {
        assetFolder + key + "." + fileExtension
    }
}

/// The media types an archive carries (text and graphs stay embedded in the scene). MED-010 adds the
/// logo: archives without one are unchanged; an app without MED-010 refuses an archive that has one.
public enum SceneArchiveAssetType: String, Sendable, Hashable, CaseIterable, Codable {
    case photo
    case video
    case logo
}

/// What a reader and writer accept (contract §3). `standard` mirrors the stores' own import caps.
public struct SceneArchiveLimits: Sendable, Equatable {
    public var maxArchiveBytes: Int
    public var maxManifestBytes: Int
    public var maxPhotoBytes: Int
    public var maxVideoBytes: Int

    public init(maxArchiveBytes: Int, maxManifestBytes: Int, maxPhotoBytes: Int, maxVideoBytes: Int) {
        self.maxArchiveBytes = maxArchiveBytes
        self.maxManifestBytes = maxManifestBytes
        self.maxPhotoBytes = maxPhotoBytes
        self.maxVideoBytes = maxVideoBytes
    }

    /// 600,000,000-byte archive, 64 KiB manifest, 40 MiB photo (`ImageImportLimits.standard`),
    /// 500 MiB video (`VideoImportLimits.standard`).
    public static let standard = SceneArchiveLimits(maxArchiveBytes: 600_000_000, maxManifestBytes: 65_536,
                                                    maxPhotoBytes: 40 * 1_024 * 1_024, maxVideoBytes: 500 * 1_024 * 1_024)

    /// Scene, one photo, one video, one logo (MED-010) and up to 20 slideshow pictures (SCN-014).
    public static let maximumFiles = 4 + SceneArchiveFormat.maximumSlides

    public func maxBytes(for type: SceneArchiveAssetType) -> Int {
        switch type {
        case .photo, .logo: maxPhotoBytes   // MED-010: the logo store's own 10 MB limit applies when staging
        case .video: maxVideoBytes
        }
    }

    /// The generic layer's limits: per-file limit is the largest of the scene and media limits;
    /// each file is checked against its own type's limit afterwards.
    var portable: PortableArchiveLimits {
        PortableArchiveLimits(maxFiles: Self.maximumFiles,
                              maxFileBytes: max(maxPhotoBytes, maxVideoBytes, 1_048_576),
                              maxManifestBytes: maxManifestBytes)
    }
}
