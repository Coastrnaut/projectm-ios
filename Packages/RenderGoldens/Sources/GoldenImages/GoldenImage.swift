// GoldenImage.swift — one captured frame as 8-bit sRGB straight-alpha RGBA, rows top-down (QA-002
// data-model "GoldenImage"). Plain Swift: builds on Linux.

public struct GoldenImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// width × height × 4 bytes: r, g, b, a per pixel.
    public let rgba: [UInt8]

    /// nil unless both sides are positive and `rgba` holds exactly width × height × 4 bytes.
    public init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384, rgba.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public var pixelCount: Int { width * height }

    /// Lowercase hex SHA-256 of the RGBA bytes (the manifest's `pixelSHA256`).
    public var pixelSHA256: String { GoldenSHA256.hex(rgba) }

    /// The pixel at (x, y), top-left origin.
    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])
    }
}
