// ScenePackPicture.swift — SCN-014-D9: a scene pack's picture is kept byte for byte when it is already a
// pixels-only copy (specs/187-scn-014-dependency-pack, research SCN-014-D9).
//
// A pack's pictures were written by this app's sanitizer on the exporting device. Re-encoding a JPEG on
// import would change its bytes and lose quality on every export → import round. The import still runs the
// sanitizer (every decoder check, size limits); when the original is the same image type and carries exactly
// the properties the fresh sanitized copy carries (container and image properties without the file size, and
// the same XMP: no location, camera, date or comment beyond what the sanitizer itself writes), the original
// bytes are stored instead of the re-encoded ones. Anything else keeps the sanitized copy.
import Foundation
import ImageIO

enum ScenePackPicture {
    /// Whether `original` may be stored in place of `sanitized` (`fileExtension`: the sanitized copy's).
    static func keepsOriginal(_ original: Data, sanitized: Data, fileExtension: String) -> Bool {
        guard let a = CGImageSourceCreateWithData(original as CFData, nil), let b = CGImageSourceCreateWithData(sanitized as CFData, nil),
              CGImageSourceGetCount(a) == 1, CGImageSourceGetCount(b) == 1,
              let typeA = CGImageSourceGetType(a), let typeB = CGImageSourceGetType(b), typeA == typeB else { return false }
        let expected: String = fileExtension == "png" ? "public.png" : "public.jpeg"
        guard (typeA as String) == expected else { return false }
        return containerProperties(a) == containerProperties(b)
            && (CGImageSourceCopyPropertiesAtIndex(a, 0, nil) as NSDictionary?) == (CGImageSourceCopyPropertiesAtIndex(b, 0, nil) as NSDictionary?)
            && xmp(a) == xmp(b)
    }

    private static func containerProperties(_ source: CGImageSource) -> NSDictionary {
        let properties = NSMutableDictionary(dictionary: (CGImageSourceCopyProperties(source, nil) as NSDictionary?) ?? [:])
        properties.removeObject(forKey: kCGImagePropertyFileSize)
        return properties
    }

    private static func xmp(_ source: CGImageSource) -> Data? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else { return nil }
        return CGImageMetadataCreateXMPData(metadata, nil) as Data?
    }
}
