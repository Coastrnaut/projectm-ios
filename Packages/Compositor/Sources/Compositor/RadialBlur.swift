// RadialBlur.swift — FX-008 "Radial blur": the value, its ranges, the sample positions and the CPU reference of one
// pixel (specs/296-fx-008-radial-blur, contracts/radial-blur.md C2, research FX-008-D2 to D5; ADR-0107). Plain Swift
// (builds on Linux). The compositor's `cmp_radial_blur` pass does the same per pixel on the GPU:
//   F  = the focus in pixels, (focusX × (width − 1), focusY × (height − 1)); s = strength;
//   out(P) = mean over k = 0…15 of input(F + (P − F) ÷ (1 + s × k ÷ 15)), each position clamped to the frame;
//   a pixel at the focus (zero spread) or with a non-finite own value is passed through.
// Every sample lies on the segment from P to F, so inside the frame; a pixel's spread is |P − F| × s ÷ (1 + s), zero at
// the focus and linear in the distance; a bright point at distance d becomes a streak from d to d × (1 + s) on its ray
// from the focus (length d × s). Inactive (off, strength 0, or a frame under 2 pixels) runs no pass: bit for bit.
import Foundation

public struct RadialBlur: Sendable, Equatable, Codable {
    /// Samples per pixel, always (FX-008-R6).
    public static let tapCount = 16
    /// Fraction: a point at distance d spreads d × strength.
    public static let strengthRange: ClosedRange<Double> = 0...0.25
    public static let defaultStrength = 0.1
    /// VoiceOver step (1%).
    public static let strengthStep = 0.01
    /// Focus as a fraction of the width (0 = left) and height (0 = top).
    public static let focusRange: ClosedRange<Double> = 0...1
    public static let defaultFocus = 0.5
    public static let focusStep = 0.05

    /// Off (the default; output bit-identical to before FX-008).
    public static let off = RadialBlur()

    public var isEnabled: Bool
    public var strength: Double
    public var focusX: Double
    public var focusY: Double

    public init(isEnabled: Bool = false, strength: Double = RadialBlur.defaultStrength,
                focusX: Double = RadialBlur.defaultFocus, focusY: Double = RadialBlur.defaultFocus) {
        self.isEnabled = isEnabled
        self.strength = strength
        self.focusX = focusX
        self.focusY = focusY
    }

    /// A user value made valid.
    public var clamped: RadialBlur {
        RadialBlur(isEnabled: isEnabled, strength: Self.clampStrength(strength), focusX: Self.clampFocus(focusX),
                   focusY: Self.clampFocus(focusY))
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampStrength(_ value: Double) -> Double {
        if value.isNaN { return defaultStrength }
        return min(max(value, strengthRange.lowerBound), strengthRange.upperBound)
    }

    /// NaN → the centre; out of range (±Inf) → the nearest edge.
    public static func clampFocus(_ value: Double) -> Double {
        if value.isNaN { return defaultFocus }
        return min(max(value, focusRange.lowerBound), focusRange.upperBound)
    }

    /// The compositor runs the pass: on, a positive strength, and at least 2 × 2 pixels.
    public func isActive(width: Int, height: Int) -> Bool {
        isEnabled && width >= 2 && height >= 2 && Self.clampStrength(strength) > 0
    }

    /// The focus in pixel coordinates (pixel centres at whole numbers).
    public func focusPixels(width: Int, height: Int) -> SIMD2<Float> {
        let x: Double = Self.clampFocus(focusX) * Double(max(width - 1, 0))
        let y: Double = Self.clampFocus(focusY) * Double(max(height - 1, 0))
        return SIMD2<Float>(Float(x), Float(y))
    }

    /// The shader block for a frame (`CMPRadialBlur`, 24 bytes).
    public func block(width: Int, height: Int) -> Block {
        Block(focus: focusPixels(width: width, height: height),
              last: SIMD2<Float>(Float(max(width - 1, 0)), Float(max(height - 1, 0))),
              strength: isEnabled ? Float(Self.clampStrength(strength)) : 0)
    }

    /// `CMPRadialBlur` in the shader.
    public struct Block: Sendable, Equatable {
        public var focus: SIMD2<Float>
        public var last: SIMD2<Float>
        public var strength: Float
    }

    // MARK: - CPU reference (contract C2)

    /// The fraction of the way from the focus to the pixel at which sample k lies: 1 ÷ (1 + s × k ÷ 15).
    public static func scale(tap k: Int, strength: Float) -> Float {
        1 / (1 + strength * Float(k) / Float(tapCount - 1))
    }

    /// The `tapCount` sample positions of pixel (x, y), clamped to the frame; sample 0 is the pixel itself.
    public static func samplePositions(x: Int, y: Int, block: Block) -> [SIMD2<Float>] {
        let d = SIMD2<Float>(Float(x), Float(y)) - block.focus
        return (0..<tapCount).map { (k: Int) -> SIMD2<Float> in
            let p: SIMD2<Float> = block.focus + d * scale(tap: k, strength: block.strength)
            return SIMD2<Float>(min(max(p.x, 0), block.last.x), min(max(p.y, 0), block.last.y))
        }
    }

    /// How far the samples of pixel (x, y) reach, in pixels: |P − F| × s ÷ (1 + s).
    public static func spread(x: Int, y: Int, block: Block) -> Float {
        let d = SIMD2<Float>(Float(x), Float(y)) - block.focus
        let distance: Float = (d * d).sum().squareRoot()
        return distance * block.strength / (1 + block.strength)
    }

    /// `a` when `t` is exactly 0, else a + t × (b − a).
    static func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        t == 0 ? a : a + t * (b - a)
    }

    /// Exact bilinear sample of `pixels` (rows top first) at a position inside the frame.
    public static func bilinear(_ pixels: [SIMD4<Float>], width: Int, height: Int, at p: SIMD2<Float>) -> SIMD4<Float> {
        let x0f: Float = p.x.rounded(.down), y0f: Float = p.y.rounded(.down)
        let fx: Float = p.x - x0f, fy: Float = p.y - y0f
        let x0 = Int(x0f), y0 = Int(y0f)
        let x1: Int = min(x0 + 1, width - 1), y1: Int = min(y0 + 1, height - 1)
        let top: SIMD4<Float> = lerp(pixels[y0 * width + x0], pixels[y0 * width + x1], fx)
        let bottom: SIMD4<Float> = lerp(pixels[y1 * width + x0], pixels[y1 * width + x1], fx)
        return lerp(top, bottom, fy)
    }

    /// One output pixel.
    public static func referencePixel(_ pixels: [SIMD4<Float>], width: Int, height: Int, x: Int, y: Int,
                                      block: Block) -> SIMD4<Float> {
        let own: SIMD4<Float> = pixels[y * width + x]
        for c in 0..<4 where !own[c].isFinite { return own }
        if SIMD2<Float>(Float(x), Float(y)) == block.focus || block.strength == 0 { return own }
        var sum: SIMD4<Float> = own
        for p in samplePositions(x: x, y: y, block: block).dropFirst() {
            sum += bilinear(pixels, width: width, height: height, at: p)
        }
        return sum / Float(tapCount)
    }

    /// The whole frame through the blur (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int) -> [SIMD4<Float>] {
        guard isActive(width: width, height: height) else { return pixels }
        let b: Block = block(width: width, height: height)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width { out.append(Self.referencePixel(pixels, width: width, height: height, x: x, y: y, block: b)) }
        }
        return out
    }
}
