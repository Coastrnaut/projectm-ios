// Scanlines.swift — FX-018 "Scanline texture": the value, its ranges, the line rule and the CPU reference
// (specs/312-fx-018-scanline-texture, contracts/scanlines.md C2, research FX-018-D2 to D5; ADR-0123). Plain Swift
// (builds on Linux). The compositor's `cmp_scanlines` pass does the same per pixel on the GPU:
//   c = the pixel's integer row y (column x when vertical), counted from 0 at the picture's top (left) pixel;
//   p = spacing (2…16 px), t = min(thickness, p − 1) (1…15 px), f = 1 − intensity (one Float per frame);
//   c mod p < t → out.rgb = in.rgb × f, out.a = in.a; otherwise out = in, bit for bit.
// Row (column) 0 is always dark; nothing scales p, so the period is in the pixels of whatever picture the chain works
// on, and there is no time input (the pattern never crawls). f ∈ [0, 1]: colour never rises and finite stays finite;
// at f = 1 the rule is the identity. Inactive (off, intensity 0, or a frame under 2 pixels) runs no pass.
import Foundation

public struct Scanlines: Sendable, Equatable, Codable {
    /// Line period in whole pixels of the picture (FX-018-R2).
    public static let spacingRange: ClosedRange<Int> = 2...16
    public static let defaultSpacing = 3
    /// Line thickness in whole pixels; used as at most spacing − 1.
    public static let thicknessRange: ClosedRange<Int> = 1...15
    public static let defaultThickness = 1
    /// How dark a line is (fraction): the factor is 1 − intensity.
    public static let intensityRange: ClosedRange<Double> = 0...1
    public static let defaultIntensity = 0.5
    /// VoiceOver step (1 %).
    public static let intensityStep = 0.01

    /// Off (the default; output bit-identical to before FX-018).
    public static let off = Scanlines()

    public var isEnabled: Bool
    public var spacing: Int
    public var thickness: Int
    public var intensity: Double
    /// Vertical lines (columns) instead of horizontal lines (rows).
    public var isVertical: Bool

    public init(isEnabled: Bool = false, spacing: Int = Scanlines.defaultSpacing,
                thickness: Int = Scanlines.defaultThickness, intensity: Double = Scanlines.defaultIntensity,
                isVertical: Bool = false) {
        self.isEnabled = isEnabled
        self.spacing = spacing
        self.thickness = thickness
        self.intensity = intensity
        self.isVertical = isVertical
    }

    /// A user value made valid (thickness kept as stored within its own range; `effectiveThickness` applies the spacing).
    public var clamped: Scanlines {
        Scanlines(isEnabled: isEnabled, spacing: Self.clampSpacing(spacing), thickness: Self.clampThickness(thickness),
                  intensity: Self.clampIntensity(intensity), isVertical: isVertical)
    }

    /// Out of range → the nearest bound.
    public static func clampSpacing(_ value: Int) -> Int {
        min(max(value, spacingRange.lowerBound), spacingRange.upperBound)
    }

    /// NaN → the default; rounded to whole pixels; out of range (±Inf) → the nearest bound.
    public static func clampSpacing(_ value: Double) -> Int {
        clampInt(value, spacingRange, defaultSpacing)
    }

    public static func clampThickness(_ value: Int) -> Int {
        min(max(value, thicknessRange.lowerBound), thicknessRange.upperBound)
    }

    public static func clampThickness(_ value: Double) -> Int {
        clampInt(value, thicknessRange, defaultThickness)
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampIntensity(_ value: Double) -> Double {
        if value.isNaN { return defaultIntensity }
        return min(max(value, intensityRange.lowerBound), intensityRange.upperBound)
    }

    private static func clampInt(_ value: Double, _ range: ClosedRange<Int>, _ fallback: Int) -> Int {
        if value.isNaN { return fallback }
        let bounded: Double = min(max(value.rounded(), Double(range.lowerBound)), Double(range.upperBound))
        return Int(bounded)
    }

    /// The thickness drawn: the stored thickness, at most spacing − 1 (every period keeps an untouched row).
    public var effectiveThickness: Int {
        min(Self.clampThickness(thickness), Self.clampSpacing(spacing) - 1)
    }

    /// The colour factor of a line pixel, 1 − intensity, as the shader gets it.
    public var factor: Float {
        Float(1 - Self.clampIntensity(intensity))
    }

    /// The compositor runs the pass: on, a positive intensity, and at least 2 × 2 pixels.
    public func isActive(width: Int, height: Int) -> Bool {
        isEnabled && width >= 2 && height >= 2 && Self.clampIntensity(intensity) > 0
    }

    /// The shader block (`CMPScanlines`, 16 bytes). Disabled gives factor 1 (the identity if run).
    public var block: Block {
        Block(period: UInt32(Self.clampSpacing(spacing)), thickness: UInt32(effectiveThickness),
              vertical: isVertical ? 1 : 0, factor: isEnabled ? factor : 1)
    }

    /// `CMPScanlines` in the shader.
    public struct Block: Sendable, Equatable {
        public var period: UInt32
        public var thickness: UInt32
        public var vertical: UInt32
        public var factor: Float

        public init(period: UInt32, thickness: UInt32, vertical: UInt32, factor: Float) {
            self.period = period
            self.thickness = thickness
            self.vertical = vertical
            self.factor = factor
        }
    }

    // MARK: - CPU reference (contract C2)

    /// Whether pixel (x, y) lies in a line.
    public static func isDark(x: Int, y: Int, block: Block) -> Bool {
        let c: Int = block.vertical != 0 ? x : y
        return c % Int(block.period) < Int(block.thickness)
    }

    /// One output pixel.
    public static func referencePixel(_ input: SIMD4<Float>, x: Int, y: Int, block: Block) -> SIMD4<Float> {
        guard isDark(x: x, y: y, block: block) else { return input }
        let f: Float = block.factor
        return SIMD4<Float>(input.x * f, input.y * f, input.z * f, input.w)
    }

    /// The whole frame through the scanlines (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int) -> [SIMD4<Float>] {
        guard isActive(width: width, height: height) else { return pixels }
        let b: Block = block
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width { out.append(Self.referencePixel(pixels[y * width + x], x: x, y: y, block: b)) }
        }
        return out
    }
}
