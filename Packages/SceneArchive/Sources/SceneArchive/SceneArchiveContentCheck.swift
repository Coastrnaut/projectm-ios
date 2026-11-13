// SceneArchiveContentCheck.swift — what an asset's bytes are, checked before any decoder sees them
// (FILE-001-R8; research FILE-001-D3).
//
// Order: size against its type's limit; SHD-011's executable and archive signatures on the first
// 64 KiB; then the declared type: `png`/`jpg` must walk as PNG/JPEG (MED-014 ImageHeaderSniffer),
// `mov` as an ISO/QuickTime movie (MED-014 MovieContainerSniffer). Bounded walks only; nothing is
// decoded, written or loaded.
import Foundation
import GeneratorGraphImport
import MediaSniffing

public enum SceneArchiveContentCheck {
    static let signatureWindow = 65_536

    public static func check(_ data: Data, path: String, type: SceneArchiveAssetType, fileExtension: String,
                             limits: SceneArchiveLimits) throws(SceneArchiveError) {
        guard data.count <= limits.maxBytes(for: type) else { throw .assetTooLarge(path) }
        switch ExecutableSignature.classify([UInt8](data.prefix(signatureWindow))) {
        case let .executable(kind)?: throw .executableContent(path: path, kind: kind)
        case .archive?: throw .nestedArchive(path)
        case nil: break
        }
        switch fileExtension {
        case "png", "jpg":
            let expected: ImageContainer = fileExtension == "png" ? .png : .jpeg
            guard let facts = try? ImageHeaderSniffer.sniff(data), facts.container == expected else { throw .wrongContent(path) }
        case "mov":
            guard (try? MovieContainerSniffer.sniff(DataByteSource(data))) != nil else { throw .wrongContent(path) }
        default:
            throw .wrongContent(path)
        }
    }
}
