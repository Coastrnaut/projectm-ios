// SceneArchiveError.swift — every reason an archive is not written or not read, each with one
// readable message (FILE-001-R4, R7-R9, R14; contract §4).
import GeneratorGraphImport
import LocalPortability
import SceneFormat

public enum SceneArchiveError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The file is larger than the archive limit (checked before reading).
    case archiveTooLarge(limit: Int)
    /// The ZIP or generic manifest layer refused it (PRE-014).
    case archive(PortableArchiveError)
    /// `scene` or `assets` in the manifest are missing or wrong, in words.
    case malformedManifest(String)
    /// More than one asset of this type (the stores hold one photo and one video).
    case tooManyMedia(SceneArchiveAssetType)
    case missingScene
    /// An asset record's file is not in the archive's file list.
    case missingAssetFile(String)
    /// SCN-001 refused `scene.json`.
    case sceneRefused(SceneDecodeError)
    /// SCN-001 validation found errors (export or import).
    case sceneInvalid([SceneIssue])
    /// The scene's photo/video asset and the manifest's records disagree for this key.
    case mismatch(key: String)
    /// A listed file that is neither the scene nor an asset.
    case unexpectedFile(String)
    case executableContent(path: String, kind: ExecutableKind)
    case nestedArchive(String)
    /// The bytes are not of the type the path declares.
    case wrongContent(String)
    case assetTooLarge(String)
    /// Export: the scene's photo/video asset has no media bytes (not in the stores).
    case missingMedia(key: String)
    /// Export: the destination could not be written.
    case writeFailed
    /// SCN-014: the slides and the photo asset's slideshow disagree for this key.
    case slideMismatch(key: String)
    /// SCN-014: a manifest or scene string names a location on a disk.
    case absolutePath(String)

    public var message: String {
        switch self {
        case let .archiveTooLarge(limit):
            "The scene archive is larger than \(limit) bytes."
        case let .archive(error):
            error.message
        case let .malformedManifest(what):
            "The scene archive's manifest is damaged (\(what))."
        case let .tooManyMedia(type):
            "The scene has more than one \(type.rawValue); the app keeps one \(type.rawValue) at a time."
        case .missingScene:
            "The archive contains no scene."
        case let .missingAssetFile(path):
            "\(path) is named by the manifest but missing from the archive."
        case let .sceneRefused(error):
            "The scene could not be read: \(error.message)"
        case let .sceneInvalid(issues):
            "The scene has errors: " + issues.map(\.message).joined(separator: " ")
        case let .mismatch(key):
            "The scene and the archive's manifest disagree about asset \"\(key)\"."
        case let .unexpectedFile(path):
            "\(path) in the archive is not part of a scene."
        case let .executableContent(path, kind):
            "\(path) in the archive is \(kind.description); programs are never imported."
        case let .nestedArchive(path):
            "\(path) in the archive is itself an archive; archives inside archives are never imported."
        case let .wrongContent(path):
            "\(path) in the archive is not the kind of file its name says."
        case let .assetTooLarge(path):
            "\(path) in the archive is larger than the app imports."
        case let .missingMedia(key):
            "Asset \"\(key)\" is not on this device, so the scene cannot be packed with it."
        case .writeFailed:
            "The scene archive could not be saved."
        case let .slideMismatch(key):
            "The slideshow of asset \"\(key)\" and the archive's pictures disagree."
        case .absolutePath:
            "The scene names a file location on this device, so it cannot be packed."
        }
    }

    public var description: String { message }
}
