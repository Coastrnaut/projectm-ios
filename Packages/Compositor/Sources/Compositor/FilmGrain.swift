// FilmGrain.swift — FX-017 "Film grain": the value, its ranges, the grain clock, the integer hash and the CPU reference
// (specs/311-fx-017-film-grain, contracts/film-grain.md C2, research FX-017-D2 to D5; ADR-0122). Plain Swift (builds on
// Linux). The compositor's `cmp_film_grain` pass does the same per pixel on the GPU:
//   cell (cx, cy) = (x ÷ size, y ÷ size); for channel ch (0 for r, g, b in monochrome; 0, 1, 2 in colour):
//   h = pcg(cx + pcg(cy + pcg(frame + pcg(seed × 4 + ch)))) (32-bit wrapping; PCG hash, Jarzynski and Olano);
//   n = Float(h >> 8) × 2⁻²³ − 1 (exact, in [−1, 1)); d = (scale × n) × alpha; out = max(c + d, min(c, 0)); alpha kept.
// scale = opacity × 0.08: zero-mean, the peak change bounded; at scale 0 the output is the input bit for bit. Inactive
// (off, opacity 0, or a frame under 2 pixels) runs no pass: the original frame bit for bit. The grain frame is 0 (static)
// unless "Vary over time" is on and Reduce flashing is off; then it advances once per 41 666 667 ns of the frame's
// injected presentation time (at most 24 times a second, whatever the display rate).
import Foundation

public struct FilmGrain: Sendable, Equatable, Codable {
    /// Strength (fraction of the bounded amplitude).
    public static let opacityRange: ClosedRange<Double> = 0...1
    public static let defaultOpacity = 0.3
    /// VoiceOver step (1 %).
    public static let opacityStep = 0.01
    /// Grain cell edge in pixels.
    public static let sizeRange: ClosedRange<Int> = 1...3
    public static let defaultSize = 1
    /// Pattern seed.
    public static let seedRange: ClosedRange<Int> = 0...9_999
    public static let defaultSeed = 1
    /// The largest change of a channel at opacity 1 and alpha 1 (linear light, fraction of white).
    public static let amplitude: Float = 0.08
    /// One grain-clock step (just over 1⁄24 s), so the grain changes at most 24 times a second.
    public static let framePeriodNanoseconds: UInt64 = 41_666_667

    /// Off (the default; output bit-identical to before FX-017).
    public static let off = FilmGrain()

    public var isEnabled: Bool
    public var opacity: Double
    public var size: Int
    /// Colour grain (three hash channels); false = monochrome (one value for red, green and blue).
    public var isColor: Bool
    public var seed: Int
    /// "Vary over time": the grain frame follows the grain clock.
    public var isAnimated: Bool

    public init(isEnabled: Bool = false, opacity: Double = FilmGrain.defaultOpacity, size: Int = FilmGrain.defaultSize,
                isColor: Bool = false, seed: Int = FilmGrain.defaultSeed, isAnimated: Bool = false) {
        self.isEnabled = isEnabled
        self.opacity = opacity
        self.size = size
        self.isColor = isColor
        self.seed = seed
        self.isAnimated = isAnimated
    }

    /// A user value made valid.
    public var clamped: FilmGrain {
        FilmGrain(isEnabled: isEnabled, opacity: Self.clampOpacity(opacity), size: Self.clampSize(size), isColor: isColor,
                  seed: Self.clampSeed(seed), isAnimated: isAnimated)
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampOpacity(_ value: Double) -> Double {
        if value.isNaN { return defaultOpacity }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    public static func clampSize(_ value: Int) -> Int { min(max(value, sizeRange.lowerBound), sizeRange.upperBound) }

    public static func clampSeed(_ value: Int) -> Int { min(max(value, seedRange.lowerBound), seedRange.upperBound) }

    /// A stored or scene number as a size: rounded; NaN → the default; out of range → the nearest bound.
    public static func size(fromNumber value: Double) -> Int {
        whole(value, sizeRange, defaultSize)
    }

    /// A stored or scene number as a seed: rounded; NaN → the default; out of range → the nearest bound.
    public static func seed(fromNumber value: Double) -> Int {
        whole(value, seedRange, defaultSeed)
    }

    private static func whole(_ value: Double, _ range: ClosedRange<Int>, _ fallback: Int) -> Int {
        if value.isNaN { return fallback }
        let bounded: Double = min(max(value.rounded(), Double(range.lowerBound)), Double(range.upperBound))
        return Int(bounded)
    }

    /// The compositor runs the pass: on, a positive opacity, and at least 2 × 2 pixels.
    public func isActive(width: Int, height: Int) -> Bool {
        isEnabled && width >= 2 && height >= 2 && Self.clampOpacity(opacity) > 0
    }

    /// The value the app hands the compositors: Reduce Motion makes the grain static (FX-017-R4, research D4).
    public func effective(reduceMotion: Bool) -> FilmGrain {
        var value = self
        if reduceMotion { value.isAnimated = false }
        return value
    }

    /// The grain frame of a frame: 0 when static or under Reduce flashing, else the grain-clock step (mod 2³²).
    public func grainFrame(presentationTimeNanoseconds: UInt64, reduceFlashing: Bool) -> UInt32 {
        guard isAnimated, !reduceFlashing else { return 0 }
        return UInt32(truncatingIfNeeded: presentationTimeNanoseconds / Self.framePeriodNanoseconds)
    }

    /// The change scale (opacity × amplitude), 0 when off.
    public var scale: Float { isEnabled ? Float(Self.clampOpacity(opacity)) * Self.amplitude : 0 }

    /// The shader block for a frame (`CMPFilmGrain`, 32 bytes).
    public func block(frame: UInt32) -> Block {
        Block(scale: scale, size: UInt32(Self.clampSize(size)), seed: UInt32(Self.clampSeed(seed)), frame: frame,
              channels: isColor ? 3 : 1, pad0: 0, pad1: 0, pad2: 0)
    }

    /// `CMPFilmGrain` in the shader.
    public struct Block: Sendable, Equatable {
        public var scale: Float
        public var size: UInt32
        public var seed: UInt32
        public var frame: UInt32
        public var channels: UInt32
        public var pad0: UInt32
        public var pad1: UInt32
        public var pad2: UInt32
    }

    // MARK: - CPU reference (contract C2)

    /// The PCG hash (32-bit wrapping), as `cmp_pcg` in the shader.
    public static func pcg(_ v: UInt32) -> UInt32 {
        let state: UInt32 = v &* 747_796_405 &+ 2_891_336_453
        let word: UInt32 = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277_803_737
        return (word >> 22) ^ word
    }

    /// The grain hash of cell (cx, cy) for a seed, grain frame and channel.
    public static func hash(cellX: UInt32, cellY: UInt32, seed: UInt32, frame: UInt32, channel: UInt32) -> UInt32 {
        let a: UInt32 = pcg(seed &* 4 &+ channel)
        let b: UInt32 = pcg(frame &+ a)
        let c: UInt32 = pcg(cellY &+ b)
        return pcg(cellX &+ c)
    }

    /// The noise of a hash: a multiple of 2⁻²³ in [−1, 1), exact in Float.
    public static func noise(_ hash: UInt32) -> Float {
        Float(hash >> 8) * 0x1p-23 - 1
    }

    /// The noise of pixel (x, y), channel 0…2 (channel 0 for every colour in monochrome).
    public static func noise(x: Int, y: Int, channel: Int, block: Block) -> Float {
        let s: UInt32 = max(block.size, 1)
        let ch: UInt32 = block.channels == 3 ? UInt32(channel) : 0
        let h: UInt32 = hash(cellX: UInt32(x) / s, cellY: UInt32(y) / s, seed: block.seed, frame: block.frame, channel: ch)
        return noise(h)
    }

    /// One channel: max(c + d, min(c, 0)), the input itself at d = 0.
    static func blend(_ c: Float, _ d: Float) -> Float {
        max(c + d, min(c, 0))
    }

    /// One output pixel.
    public static func referencePixel(_ input: SIMD4<Float>, x: Int, y: Int, block: Block) -> SIMD4<Float> {
        if block.scale == 0 { return input }
        let a: Float = input.w
        let dr: Float = block.scale * noise(x: x, y: y, channel: 0, block: block) * a
        let dg: Float = block.scale * noise(x: x, y: y, channel: 1, block: block) * a
        let db: Float = block.scale * noise(x: x, y: y, channel: 2, block: block) * a
        return SIMD4<Float>(blend(input.x, dr), blend(input.y, dg), blend(input.z, db), a)
    }

    /// The whole frame with grain (the input itself when inactive).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int, frame: UInt32) -> [SIMD4<Float>] {
        guard isActive(width: width, height: height) else { return pixels }
        let b: Block = block(frame: frame)
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width { out.append(Self.referencePixel(pixels[y * width + x], x: x, y: y, block: b)) }
        }
        return out
    }
}
