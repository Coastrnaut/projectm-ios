// Mosaic.swift — FX-012 "Mosaic pixelation": the value, its ranges, the cell assignment and the CPU reference
// (specs/299-fx-012-mosaic-pixelation, contracts/mosaic.md C2, research FX-012-D2 to D5; ADR-0110). Plain Swift
// (builds on Linux). The compositor's `cmp_mosaic` pass does the same per pixel on the GPU:
//   square:  pixel (x, y) is in block (⌊x/N⌋, ⌊y/N⌋), anchored at the frame's top-left; it shows the pixel
//            (bx·N + ⌊N/2⌋, by·N + ⌊N/2⌋);
//   hexagon: pointy-top cells, centre spacing N in a row and (√3/2)·N between rows, cell (0, 0) centred on the top-left
//            corner; the pixel centre (x + ½, y + ½) takes the nearest cell centre (cube rounding) and shows the pixel
//            containing that centre;
//   every shown position is clamped to the frame and read exactly (no filter), so every output value is an input value.
// Inactive (off, block size 1, or a frame under 2 pixels) runs no pass: the original frame bit for bit.
import Foundation

/// FX-012: the cell shape.
public enum MosaicShape: String, Sendable, Equatable, Codable, CaseIterable {
    case square
    case hexagon
}

public struct Mosaic: Sendable, Equatable, Codable {
    /// Block size in whole pixels of the picture (FX-012-R2).
    public static let sizeRange: ClosedRange<Int> = 1...64
    public static let defaultSize = 8
    /// √3 as the shader writes it (the same Float in both).
    public static let root3: Float = 1.7320508

    /// Off (the default; output bit-identical to before FX-012).
    public static let off = Mosaic()

    public var isEnabled: Bool
    public var blockSize: Int
    public var shape: MosaicShape

    public init(isEnabled: Bool = false, blockSize: Int = Mosaic.defaultSize, shape: MosaicShape = .square) {
        self.isEnabled = isEnabled
        self.blockSize = blockSize
        self.shape = shape
    }

    /// A user value made valid.
    public var clamped: Mosaic {
        Mosaic(isEnabled: isEnabled, blockSize: Self.clampSize(blockSize), shape: shape)
    }

    /// Out of range → the nearest bound.
    public static func clampSize(_ value: Int) -> Int {
        min(max(value, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// NaN → the default; rounded to whole pixels; out of range (±Inf) → the nearest bound.
    public static func clampSize(_ value: Double) -> Int {
        if value.isNaN { return defaultSize }
        let bounded: Double = min(max(value.rounded(), Double(sizeRange.lowerBound)), Double(sizeRange.upperBound))
        return Int(bounded)
    }

    /// The compositor runs the pass: on, a block of at least 2 pixels, and at least 2 × 2 pixels.
    public func isActive(width: Int, height: Int) -> Bool {
        isEnabled && width >= 2 && height >= 2 && Self.clampSize(blockSize) >= 2
    }

    /// The shader block for a frame (`CMPMosaic`, 16 bytes).
    public func block(width: Int, height: Int) -> Block {
        Block(size: UInt32(Self.clampSize(blockSize)), shape: shape == .hexagon ? 1 : 0,
              last: SIMD2<UInt32>(UInt32(max(width - 1, 0)), UInt32(max(height - 1, 0))))
    }

    /// `CMPMosaic` in the shader.
    public struct Block: Sendable, Equatable {
        public var size: UInt32
        public var shape: UInt32
        public var last: SIMD2<UInt32>
    }

    // MARK: - Cell assignment (contract C2)

    /// The square block of pixel (x, y).
    public static func squareCell(x: Int, y: Int, size: Int) -> SIMD2<Int> {
        SIMD2<Int>(x / size, y / size)
    }

    /// The unclamped centre pixel of square block `cell`.
    public static func squareCentre(_ cell: SIMD2<Int>, size: Int) -> SIMD2<Int> {
        cell &* size &+ SIMD2<Int>(repeating: size / 2)
    }

    /// The hexagonal cell (axial q, r) of pixel (x, y): the nearest pointy-top cell centre to the pixel centre.
    public static func hexCell(x: Int, y: Int, size: Int) -> SIMD2<Int> {
        let n = Float(size)
        let px: Float = Float(x) + 0.5
        let py: Float = Float(y) + 0.5
        let rf: Float = (2 * py) / (root3 * n)
        let qf: Float = px / n - rf * 0.5
        let sf: Float = -qf - rf
        var q: Float = qf.rounded()
        var r: Float = rf.rounded()
        let s: Float = sf.rounded()
        let dq: Float = abs(q - qf), dr: Float = abs(r - rf), ds: Float = abs(s - sf)
        if dq > dr && dq > ds {
            q = -r - s
        } else if dr > ds {
            r = -q - s
        }
        return SIMD2<Int>(Int(q), Int(r))
    }

    /// The centre of hexagonal cell (q, r) in pixel units (continuous; pixel i covers [i, i + 1)).
    public static func hexCentre(_ cell: SIMD2<Int>, size: Int) -> SIMD2<Float> {
        let n = Float(size)
        let q = Float(cell.x), r = Float(cell.y)
        return SIMD2<Float>(n * (q + r * 0.5), root3 * n * r * 0.5)
    }

    /// The pixel whose colour pixel (x, y) shows, clamped to the frame.
    public static func samplePixel(x: Int, y: Int, block: Block) -> SIMD2<Int> {
        let size = Int(block.size)
        let last = SIMD2<Int>(Int(block.last.x), Int(block.last.y))
        let c: SIMD2<Int>
        if block.shape == 1 {
            let centre: SIMD2<Float> = hexCentre(hexCell(x: x, y: y, size: size), size: size)
            c = SIMD2<Int>(Int(centre.x.rounded(.down)), Int(centre.y.rounded(.down)))
        } else {
            c = squareCentre(squareCell(x: x, y: y, size: size), size: size)
        }
        return SIMD2<Int>(min(max(c.x, 0), last.x), min(max(c.y, 0), last.y))
    }

    /// The whole frame through the mosaic (the input itself when inactive). Generic over the pixel type.
    public func reference<Pixel>(_ pixels: [Pixel], width: Int, height: Int) -> [Pixel] {
        guard isActive(width: width, height: height) else { return pixels }
        let b: Block = block(width: width, height: height)
        var out: [Pixel] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let p: SIMD2<Int> = Self.samplePixel(x: x, y: y, block: b)
                out.append(pixels[p.y * width + p.x])
            }
        }
        return out
    }
}
