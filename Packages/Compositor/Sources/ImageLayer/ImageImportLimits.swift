// ImageImportLimits.swift — the import limits and typed errors of a still image (MED-001-R5, R11,
// R12; research MED-001-D4; contracts/image-layer.md). Plain Swift, every platform.
//
// The limits are checked in order of cost: the file size before anything is read beyond it, the
// pixel count before any pixel is decoded, and the stored size bounds the decoded picture. MED-014
// (safe media decoder) may tighten them or add checks behind `ImageDecoding`.

public struct ImageImportLimits: Sendable, Equatable {
    /// A picked file larger than this is refused (`.tooLarge`).
    public var maxFileBytes: Int64
    /// A picture with more pixels (width × height) is refused before decoding (`.tooManyPixels`).
    public var maxPixelCount: Int
    /// The decoded and stored picture is scaled down (aspect kept) to at most this many pixels on
    /// its longest side.
    public var maxStoredLongestSide: Int

    public init(maxFileBytes: Int64, maxPixelCount: Int, maxStoredLongestSide: Int) {
        self.maxFileBytes = max(maxFileBytes, 1)
        self.maxPixelCount = max(maxPixelCount, 1)
        self.maxStoredLongestSide = max(maxStoredLongestSide, 1)
    }

    /// 40 MB, 100 million pixels, 4096 px (spec Clarifications).
    public static let standard = ImageImportLimits(maxFileBytes: 40 * 1024 * 1024, maxPixelCount: 100_000_000,
                                                   maxStoredLongestSide: 4096)

    /// The size of a `width` × `height` picture scaled down so its longest side is at most
    /// `maxStoredLongestSide` (never scaled up; each side at least 1).
    public func storedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxStoredLongestSide, width > 0, height > 0 else { return (max(width, 1), max(height, 1)) }
        let scale = Double(maxStoredLongestSide) / Double(longest)
        return (max(Int((Double(width) * scale).rounded()), 1), max(Int((Double(height) * scale).rounded()), 1))
    }
}

/// Why an image was not imported or could not be loaded.
public enum ImageImportError: Error, Sendable, Equatable {
    /// Not an image the system can decode.
    case notAnImage
    /// The file is larger than `maxFileBytes`.
    case tooLarge
    /// The picture has more than `maxPixelCount` pixels.
    case tooManyPixels
    /// The data says it is an image but cannot be decoded.
    case damaged
    /// The picked file could not be read.
    case unreadable
    /// The copy could not be written to the app's storage.
    case saveFailed

    /// The notice text (MED-001-R11).
    public var message: String {
        switch self {
        case .notAnImage: "That file isn't an image the app can show."
        case .tooLarge: "That image is larger than 40 MB, so it wasn't imported."
        case .tooManyPixels: "That image has more than 100 million pixels, so it wasn't imported."
        case .damaged: "That image couldn't be read. It may be damaged."
        case .unreadable: "The image couldn't be opened."
        case .saveFailed: "The photo couldn't be saved on this device."
        }
    }
}
