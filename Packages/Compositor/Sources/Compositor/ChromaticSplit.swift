// ChromaticSplit.swift — FX-006 "Chromatic split": the value, its ranges, the sample-position maths and the CPU
// reference of one pixel (specs/293-fx-006-chromatic-split, contracts/chromatic-split.md C2, research FX-006-D2 to D5;
// ADR-0104). Plain Swift (builds on Linux). The compositor's `cmp_chromatic` pass does the same per pixel on the GPU:
//   v  = Amount × shorter side along Angle (0° = red moves right, 90° = red moves up), or radial: grows from the
//        centre to Amount at the corners;
//   v' = v × min(1, e ÷ max(amount in pixels, 1)), e = the pixel's distance (in pixels) to the nearest border, so the
//        outermost ring is unchanged and |v'| ≤ e keeps every sample inside the frame; samples are clamped as well;
//   out = own pixel when v' = 0 or the own pixel is non-finite; else (R at p − v', G own, B at p + v',
//        A = max of the three alphas), R and B filtered between the four nearest pixels (a weight of exactly 0 never
//        mixes in the neighbour).
// Inactive (off, amount 0, or a frame under 3 pixels) runs no pass: the output is the input bit for bit.
import Foundation

public struct ChromaticSplit: Sendable, Equatable, Codable {
    /// Fraction of the frame's shorter side.
    public static let amountRange: ClosedRange<Double> = 0...0.02
    public static let defaultAmount = 0.005
    /// VoiceOver step (0.1%).
    public static let amountStep = 0.001
    public static let angleRange: ClosedRange<Double> = 0...360
    public static let defaultAngle = 0.0
    public static let angleStep = 15.0

    /// Off (the default; output bit-identical to before FX-006).
    public static let off = ChromaticSplit()

    public var isEnabled: Bool
    public var amount: Double
    public var angleDegrees: Double
    public var isRadial: Bool

    public init(isEnabled: Bool = false, amount: Double = ChromaticSplit.defaultAmount,
                angleDegrees: Double = ChromaticSplit.defaultAngle, isRadial: Bool = false) {
        self.isEnabled = isEnabled
        self.amount = amount
        self.angleDegrees = angleDegrees
        self.isRadial = isRadial
    }

    /// A user value made valid.
    public var clamped: ChromaticSplit {
        ChromaticSplit(isEnabled: isEnabled, amount: Self.clampAmount(amount), angleDegrees: Self.clampAngle(angleDegrees),
                       isRadial: isRadial)
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampAmount(_ value: Double) -> Double {
        if value.isNaN { return defaultAmount }
        return min(max(value, amountRange.lowerBound), amountRange.upperBound)
    }

    /// 0…360 kept; other finite values wrap into 0..<360; NaN and ±Inf → 0.
    public static func clampAngle(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAngle }
        if angleRange.contains(value) { return value }
        let r: Double = value.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// The split length in pixels for a frame (0 when off).
    public func amountPixels(width: Int, height: Int) -> Double {
        guard isEnabled, width > 0, height > 0 else { return 0 }
        return Self.clampAmount(amount) * Double(min(width, height))
    }

    /// The compositor runs the pass: on, a positive length, and an interior (at least 3 × 3 pixels).
    public func isActive(width: Int, height: Int) -> Bool {
        width >= 3 && height >= 3 && amountPixels(width: width, height: height) > 0
    }

    /// The shader block for a frame (`CMPChromatic`, 32 bytes).
    public func block(width: Int, height: Int) -> Block {
        let pixels = Float(amountPixels(width: width, height: height))
        let radians: Double = Self.clampAngle(angleDegrees) * Double.pi / 180
        var direction = SIMD2<Float>(Float(cos(radians)), Float(-sin(radians)))   // texture y points down
        for c in 0..<2 where abs(direction[c]) < 1e-6 { direction[c] = 0 }
        let centre = SIMD2<Float>(Float(width - 1) / 2, Float(height - 1) / 2)
        let radius: Float = (centre * centre).sum().squareRoot()
        return Block(linear: direction * pixels, centre: centre, amountPixels: pixels, band: max(pixels, 1),
                     inverseRadius: radius > 0 ? 1 / radius : 0, radial: isRadial ? 1 : 0)
    }

    /// `CMPChromatic` in the shader.
    public struct Block: Sendable, Equatable {
        public var linear: SIMD2<Float>
        public var centre: SIMD2<Float>
        public var amountPixels: Float
        public var band: Float
        public var inverseRadius: Float
        public var radial: UInt32
    }

    // MARK: - CPU reference (contract C2)

    /// The split vector of pixel (x, y) after the edge fade, in pixels.
    public static func vector(x: Int, y: Int, width: Int, height: Int, block: Block) -> SIMD2<Float> {
        let q = SIMD2<Float>(Float(x), Float(y))
        var v: SIMD2<Float> = block.linear
        if block.radial != 0 { v = block.amountPixels * (q - block.centre) * block.inverseRadius }
        let e: Float = min(min(q.x, Float(width - 1) - q.x), min(q.y, Float(height - 1) - q.y))
        let fade: Float = min(max(e / block.band, 0), 1)
        return v * fade
    }

    /// A sample position clamped to the frame.
    public static func clampedPosition(_ p: SIMD2<Float>, width: Int, height: Int) -> SIMD2<Float> {
        SIMD2<Float>(min(max(p.x, 0), Float(width - 1)), min(max(p.y, 0), Float(height - 1)))
    }

    /// `a` when `t` is exactly 0 (a non-finite `b` cannot leak in), else a + t × (b − a).
    static func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        t == 0 ? a : a + t * (b - a)
    }

    /// Bilinear sample of `pixels` (rows top first) at a clamped position.
    public static func bilinear(_ pixels: [SIMD4<Float>], width: Int, height: Int, at position: SIMD2<Float>) -> SIMD4<Float> {
        let p: SIMD2<Float> = clampedPosition(position, width: width, height: height)
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
        let v: SIMD2<Float> = vector(x: x, y: y, width: width, height: height, block: block)
        if v == .zero { return own }
        let q = SIMD2<Float>(Float(x), Float(y))
        let r: SIMD4<Float> = bilinear(pixels, width: width, height: height, at: q - v)
        let b: SIMD4<Float> = bilinear(pixels, width: width, height: height, at: q + v)
        return SIMD4<Float>(r.x, own.y, b.z, max(own.w, max(r.w, b.w)))
    }

    /// The whole frame through the split (the input itself when inactive).
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
