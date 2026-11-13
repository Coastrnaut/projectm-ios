// CapturedPixels.swift — REC-001 pixel values (data-model.md). Plain Swift: builds on Linux.
import Foundation

/// One captured frame's pixels, as each renderer reads them back (research REC-001-D1).
public struct CapturedPixels: Sendable, Equatable {
    public enum Layout: Sendable, Equatable {
        /// CMP-001 composite after the flash guard: linear, premultiplied, IEEE half floats, RGBA,
        /// rows top-down, tightly packed.
        case linearPremultipliedHalfRGBA([UInt16])
        /// A native spectrum's drawable: 8-bit sRGB-encoded BGRA, rows top-down, opaque.
        case sRGBBGRA8TopDown([UInt8])
        /// projectM's framebuffer (`glReadPixels`): 8-bit display-encoded RGBA, rows bottom-up, opaque.
        case sRGBRGBA8BottomUp([UInt8])

        var count: Int {
            switch self {
            case .linearPremultipliedHalfRGBA(let v): v.count
            case .sRGBBGRA8TopDown(let v): v.count
            case .sRGBRGBA8BottomUp(let v): v.count
            }
        }
    }

    public let width: Int
    public let height: Int
    public let layout: Layout

    /// nil unless `width`, `height` > 0 and the layout holds width × height × 4 values.
    public init?(width: Int, height: Int, layout: Layout) {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384, layout.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.layout = layout
    }

    /// Whether the source carries coverage at all (only the compositor's composite does).
    public var mayHaveCoverage: Bool {
        if case .linearPremultipliedHalfRGBA = layout { return true }
        return false
    }
}

/// 8-bit sRGB pixels, straight alpha, rows top-down; every alpha byte is 255 when `hasAlpha` is false.
public struct RGBA8Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]
    public let hasAlpha: Bool

    public init(width: Int, height: Int, rgba: [UInt8], hasAlpha: Bool) {
        self.width = width
        self.height = height
        self.rgba = rgba
        self.hasAlpha = hasAlpha
    }

    /// The pixel at (x, y), top-left origin: (r, g, b, a).
    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])
    }
}

/// An encoded frame ready for the Files exporter (REC-001-R9).
public struct CapturedFrame: Sendable, Equatable {
    public let format: FrameCaptureFormat
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool
    public let data: Data

    public init(format: FrameCaptureFormat, width: Int, height: Int, hasAlpha: Bool, data: Data) {
        self.format = format
        self.width = width
        self.height = height
        self.hasAlpha = hasAlpha
        self.data = data
    }

    /// "png 1179x2556 opaque" — the DEBUG probe's text (contracts/frame-capture.md).
    public var summary: String { "\(format.rawValue) \(width)x\(height) \(hasAlpha ? "alpha" : "opaque")" }
}
