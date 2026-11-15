// EdgeOutline.swift — FX-014 "Edge outline": the value, its ranges, the colour, the ACC-012 limit and the CPU
// reference (specs/303-fx-014-edge-outline, contracts/edge-outline.md C2, research FX-014-D2 to D6; ADR-0114). Plain
// Swift (builds on Linux). The compositor's `cmp_edge_outline` pass does the same per pixel on the GPU:
//   s(dx, dy) = linear luminance (Rec. 709) of the pixel at p + (dx·width, dy·width), clamped to the frame;
//   Gx = (s(1,−1) + 2 s(1,0) + s(1,1)) − (s(−1,−1) + 2 s(−1,0) + s(−1,1));
//   Gy = (s(−1,1) + 2 s(0,1) + s(1,1)) − (s(−1,−1) + 2 s(0,−1) + s(1,−1));
//   strength = √(Gx² + Gy²) ÷ 4; mask = finite ? smoothstep(t, t + 0.1, strength) : 0;
//   overlay: mask 0 → the input pixel exactly, else mix(input, (colour, 1), mask);
//   outline only: mix((0, 0, 0, 1), (colour, 1), mask).
// Identical neighbours give identical sums, so a flat picture has strength 0 everywhere (the border too: taps are
// clamped), and the threshold's lower bound keeps rounding residue from ever drawing. Inactive (off, or a frame under 2
// pixels) runs no pass: the original frame bit for bit.
import FlashSafety
import Foundation

/// FX-014: overlay on the picture, or the outline alone on black.
public enum EdgeOutlineMode: String, Sendable, Equatable, Codable, CaseIterable {
    case overlay
    case outlineOnly
}

/// FX-014: an sRGB colour, each component 0…1.
public struct EdgeOutlineColor: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let white = EdgeOutlineColor(red: 1, green: 1, blue: 1)

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clampComponent(red)
        self.green = Self.clampComponent(green)
        self.blue = Self.clampComponent(blue)
    }

    /// NaN → 1 (white); otherwise clamped to 0…1.
    public static func clampComponent(_ value: Double) -> Double {
        if value.isNaN { return 1 }
        return min(max(value, 0), 1)
    }

    /// "RRGGBB" (upper case, no "#").
    public var hex: String {
        let parts: [Double] = [red, green, blue]
        var out = ""
        for part in parts {
            let byte = Int((part * 255).rounded())
            let text = String(byte, radix: 16, uppercase: true)
            out += byte < 16 ? "0" + text : text
        }
        return out
    }

    /// Six hex digits, with or without "#"; anything else → nil.
    public init?(hex text: String) {
        var digits: Substring = Substring(text)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// IEC 61966-2-1: an sRGB component to linear light.
    public static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    public var linearComponents: SIMD3<Float> {
        SIMD3<Float>(Float(Self.linear(red)), Float(Self.linear(green)), Float(Self.linear(blue)))
    }
}

public struct EdgeOutline: Sendable, Equatable, Codable {
    public static let thresholdRange: ClosedRange<Double> = 0.02...1
    public static let defaultThreshold = 0.2
    public static let widthRange: ClosedRange<Int> = 1...3
    public static let defaultWidth = 1
    /// The fixed soft band above the threshold (research FX-014-D3).
    public static let softBand: Float = 0.1

    /// Off (the default; output bit-identical to before FX-014).
    public static let off = EdgeOutline()

    public var isEnabled: Bool
    public var threshold: Double
    public var width: Int
    public var color: EdgeOutlineColor
    public var mode: EdgeOutlineMode
    /// ACC-012: the factor on the linear colour (1 unless an intensity limit applies); not stored.
    public var colorScale: Double

    public init(isEnabled: Bool = false, threshold: Double = EdgeOutline.defaultThreshold, width: Int = EdgeOutline.defaultWidth,
                color: EdgeOutlineColor = .white, mode: EdgeOutlineMode = .overlay, colorScale: Double = 1) {
        self.isEnabled = isEnabled
        self.threshold = threshold
        self.width = width
        self.color = color
        self.mode = mode
        self.colorScale = colorScale
    }

    /// NaN → the default; out of range → the nearest bound.
    public static func clampThreshold(_ value: Double) -> Double {
        if value.isNaN { return defaultThreshold }
        return min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    public static func clampWidth(_ value: Int) -> Int {
        min(max(value, widthRange.lowerBound), widthRange.upperBound)
    }

    /// NaN → the default; rounded; out of range (±Inf) → the nearest bound.
    public static func clampWidth(_ value: Double) -> Int {
        if value.isNaN { return defaultWidth }
        let bounded: Double = min(max(value.rounded(), Double(widthRange.lowerBound)), Double(widthRange.upperBound))
        return Int(bounded)
    }

    /// The compositor runs the pass: on and at least 2 × 2 pixels.
    public func isActive(width w: Int, height h: Int) -> Bool {
        isEnabled && w >= 2 && h >= 2
    }

    /// ACC-012-R4 (research FX-014-D6): an intensity limit below 1 scales the outline colour by the limit.
    public func limited(by clamp: SafetyClamp) -> EdgeOutline {
        var out: EdgeOutline = self
        out.colorScale = clamp.capsIntensity ? max(0, min(1, clamp.limits.intensityLimit)) : 1
        return out
    }

    /// The shader block for a frame (`CMPEdgeOutline`, 48 bytes).
    public func block(width w: Int, height h: Int) -> Block {
        let lin: SIMD3<Float> = color.linearComponents * Float(colorScale)
        return Block(colour: SIMD4<Float>(lin.x, lin.y, lin.z, 1),
                     last: SIMD2<UInt32>(UInt32(max(w - 1, 0)), UInt32(max(h - 1, 0))),
                     threshold: Float(Self.clampThreshold(threshold)), width: UInt32(Self.clampWidth(width)),
                     mode: mode == .outlineOnly ? 1 : 0)
    }

    /// `CMPEdgeOutline` in the shader.
    public struct Block: Sendable, Equatable {
        public var colour: SIMD4<Float>
        public var last: SIMD2<UInt32>
        public var threshold: Float
        public var width: UInt32
        public var mode: UInt32
    }

    // MARK: - CPU reference (contract C2)

    /// Linear luminance (Rec. 709) of a premultiplied colour.
    public static func luminance(_ p: SIMD4<Float>) -> Float {
        0.2126 * p.x + 0.7152 * p.y + 0.0722 * p.z
    }

    /// The edge strength at (x, y) of a luminance picture.
    public static func strength(_ lum: [Float], width w: Int, height h: Int, x: Int, y: Int, tap: Int) -> Float {
        func s(_ dx: Int, _ dy: Int) -> Float {
            let sx: Int = min(max(x + dx * tap, 0), w - 1)
            let sy: Int = min(max(y + dy * tap, 0), h - 1)
            return lum[sy * w + sx]
        }
        let right: Float = s(1, -1) + 2 * s(1, 0) + s(1, 1)
        let left: Float = s(-1, -1) + 2 * s(-1, 0) + s(-1, 1)
        let down: Float = s(-1, 1) + 2 * s(0, 1) + s(1, 1)
        let up: Float = s(-1, -1) + 2 * s(0, -1) + s(1, -1)
        let gx: Float = right - left
        let gy: Float = down - up
        return (gx * gx + gy * gy).squareRoot() / 4
    }

    /// The outline mask for a strength.
    public static func mask(strength: Float, threshold: Float) -> Float {
        guard strength.isFinite, strength > threshold else { return 0 }
        let t: Float = min(max((strength - threshold) / softBand, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The mask of every pixel (0 everywhere when inactive).
    public func referenceMask(_ pixels: [SIMD4<Float>], width w: Int, height h: Int) -> [Float] {
        guard isActive(width: w, height: h) else { return [Float](repeating: 0, count: pixels.count) }
        let lum: [Float] = pixels.map(Self.luminance)
        let b: Block = block(width: w, height: h)
        var out: [Float] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<h {
            for x in 0..<w {
                let e: Float = Self.strength(lum, width: w, height: h, x: x, y: y, tap: Int(b.width))
                out.append(Self.mask(strength: e, threshold: b.threshold))
            }
        }
        return out
    }

    /// The whole frame through the outline (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width w: Int, height h: Int) -> [SIMD4<Float>] {
        guard isActive(width: w, height: h) else { return pixels }
        let masks: [Float] = referenceMask(pixels, width: w, height: h)
        let b: Block = block(width: w, height: h)
        let black = SIMD4<Float>(0, 0, 0, 1)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for i in pixels.indices {
            let m: Float = masks[i]
            let base: SIMD4<Float> = b.mode == 1 ? black : pixels[i]
            if m <= 0 {
                out.append(base)
            } else {
                out.append(base + (b.colour - base) * m)
            }
        }
        return out
    }
}
