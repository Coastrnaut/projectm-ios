// DirectionalBlur.swift — FX-007 "Directional blur": the value, its ranges, the fixed 16-tap kernel and the CPU
// reference of one pixel (specs/295-fx-007-directional-blur, contracts/directional-blur.md C2, research FX-007-D2 to
// D5; ADR-0106). Plain Swift (builds on Linux). The compositor's `cmp_directional_blur` pass does the same per pixel on
// the GPU:
//   d   = (cos θ, −sin θ) in texture coordinates (y down), components under 1e-6 snapped to 0 (0° horizontal, 90°
//         vertical; the axis has no sign, so θ is 0…180°);
//   r   = Radius × the frame's shorter side, in pixels;
//   q_i = clamp(p + u_i × r × d) for i = 0…15, u_i = (2i − 15) ÷ 15 (evenly from −r to +r, both ends included);
//   out = Σ w_i × bilinear(q_i) ÷ Σ w_i over finite samples, w_i = exp(−2 u_i²) normalised (Gaussian, σ = r ÷ 2);
//         a non-finite own pixel, or no finite sample, gives the own pixel.
// Exactly 16 samples at every radius: the cost never grows with the radius. Inactive (off or a zero radius) runs no
// pass: the output is the input bit for bit.
import Foundation

public struct DirectionalBlur: Sendable, Equatable, Codable {
    /// Fraction of the frame's shorter side, reached on each side of the pixel.
    public static let radiusRange: ClosedRange<Double> = 0...0.02
    public static let defaultRadius = 0.005
    /// VoiceOver step (0.1%).
    public static let radiusStep = 0.001
    public static let angleRange: ClosedRange<Double> = 0...180
    public static let defaultAngle = 0.0
    public static let angleStep = 15.0
    /// The fixed tap budget (the shader's `cmp_dirblur_taps`).
    public static let tapCount = 16

    /// Off (the default; output bit-identical to before FX-007).
    public static let off = DirectionalBlur()

    public var isEnabled: Bool
    public var radius: Double
    public var angleDegrees: Double

    public init(isEnabled: Bool = false, radius: Double = DirectionalBlur.defaultRadius,
                angleDegrees: Double = DirectionalBlur.defaultAngle) {
        self.isEnabled = isEnabled
        self.radius = radius
        self.angleDegrees = angleDegrees
    }

    /// A user value made valid.
    public var clamped: DirectionalBlur {
        DirectionalBlur(isEnabled: isEnabled, radius: Self.clampRadius(radius), angleDegrees: Self.clampAngle(angleDegrees))
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampRadius(_ value: Double) -> Double {
        if value.isNaN { return defaultRadius }
        return min(max(value, radiusRange.lowerBound), radiusRange.upperBound)
    }

    /// 0…180 kept; other finite values fold into 0..<180 (the axis has no sign); NaN and ±Inf → 0.
    public static func clampAngle(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAngle }
        if angleRange.contains(value) { return value }
        let r: Double = value.truncatingRemainder(dividingBy: 180)
        return r < 0 ? r + 180 : r
    }

    /// The radius in pixels for a frame (0 when off).
    public func radiusPixels(width: Int, height: Int) -> Double {
        guard isEnabled, width > 0, height > 0 else { return 0 }
        return Self.clampRadius(radius) * Double(min(width, height))
    }

    /// The compositor runs the pass: on and a positive radius.
    public func isActive(width: Int, height: Int) -> Bool {
        radiusPixels(width: width, height: height) > 0
    }

    // MARK: - Kernel

    /// u_i = (2i − 15) ÷ 15: evenly from −1 to +1, both ends included.
    public static let unitOffsets: [Double] = (0..<tapCount).map { (i: Int) -> Double in
        Double(2 * i - (tapCount - 1)) / Double(tapCount - 1)
    }

    /// Gaussian weights (σ = half the radius, i.e. 0.5 in unit offsets), normalised to sum 1; independent of the radius.
    public static let weights: [Float] = {
        let raw: [Double] = unitOffsets.map { (u: Double) -> Double in exp(-u * u / (2 * 0.25)) }
        let total: Double = raw.reduce(0, +)
        return raw.map { (w: Double) -> Float in Float(w / total) }
    }()

    /// The blur axis in texture coordinates (y down).
    public static func direction(angleDegrees: Double) -> SIMD2<Float> {
        let radians: Double = clampAngle(angleDegrees) * Double.pi / 180
        var d = SIMD2<Float>(Float(cos(radians)), Float(-sin(radians)))
        for c in 0..<2 where abs(d[c]) < 1e-6 { d[c] = 0 }
        return d
    }

    /// The shader block for a frame (`CMPDirBlur`, 80 bytes): tap i sits at p + start + i × step.
    public func block(width: Int, height: Int) -> Block {
        let r = Float(radiusPixels(width: width, height: height))
        let d: SIMD2<Float> = Self.direction(angleDegrees: angleDegrees)
        let span = Float(Self.tapCount - 1)
        let w: [Float] = Self.weights
        return Block(step: d * (2 * r / span), start: -(d * r),
                     w0: SIMD4<Float>(w[0], w[1], w[2], w[3]), w1: SIMD4<Float>(w[4], w[5], w[6], w[7]),
                     w2: SIMD4<Float>(w[8], w[9], w[10], w[11]), w3: SIMD4<Float>(w[12], w[13], w[14], w[15]))
    }

    /// `CMPDirBlur` in the shader.
    public struct Block: Sendable, Equatable {
        public var step: SIMD2<Float>
        public var start: SIMD2<Float>
        public var w0: SIMD4<Float>
        public var w1: SIMD4<Float>
        public var w2: SIMD4<Float>
        public var w3: SIMD4<Float>

        public var weights: [Float] {
            [w0, w1, w2, w3].flatMap { (v: SIMD4<Float>) -> [Float] in [v.x, v.y, v.z, v.w] }
        }
    }

    // MARK: - CPU reference (contract C2)

    /// Tap `i`'s position for pixel (x, y), clamped to the frame (index space).
    public static func samplePosition(x: Int, y: Int, tap i: Int, width: Int, height: Int, block: Block) -> SIMD2<Float> {
        let q = SIMD2<Float>(Float(x), Float(y))
        let p: SIMD2<Float> = q + (block.start + Float(i) * block.step)
        return SIMD2<Float>(min(max(p.x, 0), Float(width - 1)), min(max(p.y, 0), Float(height - 1)))
    }

    /// `a` when `t` is exactly 0 (a non-finite `b` cannot leak in), else a + t × (b − a).
    static func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        t == 0 ? a : a + t * (b - a)
    }

    /// Bilinear sample of `pixels` (rows top first) at an in-frame position.
    public static func bilinear(_ pixels: [SIMD4<Float>], width: Int, height: Int, at p: SIMD2<Float>) -> SIMD4<Float> {
        let x0f: Float = p.x.rounded(.down), y0f: Float = p.y.rounded(.down)
        let fx: Float = p.x - x0f, fy: Float = p.y - y0f
        let x0 = Int(x0f), y0 = Int(y0f)
        let x1: Int = min(x0 + 1, width - 1), y1: Int = min(y0 + 1, height - 1)
        let top: SIMD4<Float> = lerp(pixels[y0 * width + x0], pixels[y0 * width + x1], fx)
        let bottom: SIMD4<Float> = lerp(pixels[y1 * width + x0], pixels[y1 * width + x1], fx)
        return lerp(top, bottom, fy)
    }

    private static func isFinite(_ v: SIMD4<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite
    }

    /// One output pixel; `samples` counts the taps read (always `tapCount`).
    public static func referencePixel(_ pixels: [SIMD4<Float>], width: Int, height: Int, x: Int, y: Int,
                                      block: Block, samples: inout Int) -> SIMD4<Float> {
        let own: SIMD4<Float> = pixels[y * width + x]
        guard isFinite(own) else { return own }
        let w: [Float] = block.weights
        var sum = SIMD4<Float>(repeating: 0)
        var total: Float = 0
        for i in 0..<tapCount {
            let p: SIMD2<Float> = samplePosition(x: x, y: y, tap: i, width: width, height: height, block: block)
            let s: SIMD4<Float> = bilinear(pixels, width: width, height: height, at: p)
            samples += 1
            guard isFinite(s) else { continue }
            sum += w[i] * s
            total += w[i]
        }
        return total > 0 ? sum / total : own
    }

    /// The whole frame through the blur (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int) -> [SIMD4<Float>] {
        var samples = 0
        return reference(pixels, width: width, height: height, samples: &samples)
    }

    /// As `reference`, counting every tap read (tests: `tapCount` per pixel at every radius).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int, samples: inout Int) -> [SIMD4<Float>] {
        guard isActive(width: width, height: height) else { return pixels }
        let b: Block = block(width: width, height: height)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                out.append(Self.referencePixel(pixels, width: width, height: height, x: x, y: y, block: b, samples: &samples))
            }
        }
        return out
    }
}
