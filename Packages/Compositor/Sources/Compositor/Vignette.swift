// Vignette.swift — FX-015 "Vignette": the value, its ranges, the falloff weight and the CPU reference
// (specs/305-fx-015-vignette, contracts/vignette.md C2, research FX-015-D2 to D5; ADR-0116). Plain Swift (builds on
// Linux). The compositor's `cmp_vignette` pass does the same per pixel on the GPU:
//   P = the pixel centre (x + ½, y + ½); C = (centerX × W, centerY × H); s = (2 ÷ W, 2 ÷ H) ÷ √2;
//   d = |(P − C) ⊙ s| (an ellipse following the frame; its corners are at d = 1 from its middle);
//   t = clamp((d − (1 − softness)) ÷ softness, 0, 1); w = t² × (3 − 2t);
//   out.rgb = in.rgb × (1 − intensity × w); out.a = in.a.
// The factor lies in [0, 1], so colour never rises and finite stays finite; where w = 0 (the clear core, the centre
// always) it is exactly 1 and the pixel is bit-exact. Inactive (off, intensity 0, or a frame under 2 pixels) runs no
// pass: the original frame bit for bit.
import Foundation

public struct Vignette: Sendable, Equatable, Codable {
    /// How dark the falloff gets at distance 1 and beyond (fraction).
    public static let intensityRange: ClosedRange<Double> = 0...1
    public static let defaultIntensity = 0.5
    /// VoiceOver step (1 %).
    public static let intensityStep = 0.01
    /// Width of the falloff band (fraction of the centre-to-corner distance); the clear core is 1 − softness.
    public static let softnessRange: ClosedRange<Double> = 0.1...0.9
    public static let defaultSoftness = 0.5
    public static let softnessStep = 0.05
    /// Centre as a fraction of the width (0 = left edge) and height (0 = top edge).
    public static let centerRange: ClosedRange<Double> = 0...1
    public static let defaultCenter = 0.5
    public static let centerStep = 0.05
    /// 1 ÷ √2 as both the CPU and the block use it.
    static let inverseRoot2: Float = 0.70710677

    /// Off (the default; output bit-identical to before FX-015).
    public static let off = Vignette()

    public var isEnabled: Bool
    public var intensity: Double
    public var softness: Double
    public var centerX: Double
    public var centerY: Double

    public init(isEnabled: Bool = false, intensity: Double = Vignette.defaultIntensity,
                softness: Double = Vignette.defaultSoftness, centerX: Double = Vignette.defaultCenter,
                centerY: Double = Vignette.defaultCenter) {
        self.isEnabled = isEnabled
        self.intensity = intensity
        self.softness = softness
        self.centerX = centerX
        self.centerY = centerY
    }

    /// A user value made valid.
    public var clamped: Vignette {
        Vignette(isEnabled: isEnabled, intensity: Self.clampIntensity(intensity), softness: Self.clampSoftness(softness),
                 centerX: Self.clampCenter(centerX), centerY: Self.clampCenter(centerY))
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampIntensity(_ value: Double) -> Double {
        clamp(value, intensityRange, defaultIntensity)
    }

    public static func clampSoftness(_ value: Double) -> Double {
        clamp(value, softnessRange, defaultSoftness)
    }

    public static func clampCenter(_ value: Double) -> Double {
        clamp(value, centerRange, defaultCenter)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        if value.isNaN { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The compositor runs the pass: on, a positive intensity, and at least 2 × 2 pixels.
    public func isActive(width: Int, height: Int) -> Bool {
        isEnabled && width >= 2 && height >= 2 && Self.clampIntensity(intensity) > 0
    }

    /// The shader block for a frame (`CMPVignette`, 32 bytes).
    public func block(width: Int, height: Int) -> Block {
        let w = Float(max(width, 1)), h = Float(max(height, 1))
        let soft = Float(Self.clampSoftness(softness))
        return Block(centre: SIMD2<Float>(Float(Self.clampCenter(centerX)) * w, Float(Self.clampCenter(centerY)) * h),
                     scale: SIMD2<Float>(2 / w, 2 / h) * Self.inverseRoot2,
                     inner: 1 - soft, softness: soft,
                     intensity: isEnabled ? Float(Self.clampIntensity(intensity)) : 0, pad: 0)
    }

    /// `CMPVignette` in the shader.
    public struct Block: Sendable, Equatable {
        public var centre: SIMD2<Float>
        public var scale: SIMD2<Float>
        public var inner: Float
        public var softness: Float
        public var intensity: Float
        public var pad: Float
    }

    // MARK: - CPU reference (contract C2)

    /// The elliptical distance of pixel (x, y) from the centre (1 at the frame's corners when centred).
    public static func distance(x: Int, y: Int, block: Block) -> Float {
        let dx: Float = (Float(x) + 0.5 - block.centre.x) * block.scale.x
        let dy: Float = (Float(y) + 0.5 - block.centre.y) * block.scale.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The falloff weight w (0 in the clear core, 1 at distance 1 and beyond).
    public static func weight(distance d: Float, block: Block) -> Float {
        let t: Float = min(max((d - block.inner) / block.softness, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The colour factor 1 − intensity × w of pixel (x, y).
    public static func factor(x: Int, y: Int, block: Block) -> Float {
        1 - block.intensity * weight(distance: distance(x: x, y: y, block: block), block: block)
    }

    /// One output pixel.
    public static func referencePixel(_ input: SIMD4<Float>, x: Int, y: Int, block: Block) -> SIMD4<Float> {
        let f: Float = factor(x: x, y: y, block: block)
        return SIMD4<Float>(input.x * f, input.y * f, input.z * f, input.w)
    }

    /// The whole frame through the vignette (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int) -> [SIMD4<Float>] {
        guard isActive(width: width, height: height) else { return pixels }
        let b: Block = block(width: width, height: height)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width { out.append(Self.referencePixel(pixels[y * width + x], x: x, y: y, block: b)) }
        }
        return out
    }
}
