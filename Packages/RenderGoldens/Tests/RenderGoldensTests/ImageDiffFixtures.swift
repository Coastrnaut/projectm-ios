// ImageDiffFixtures.swift — QA-003-T05: seeded fixture images for the visual diff tests (research D7).
// A horizontal/vertical gradient background with a filled rectangle and a filled circle, plus noise
// and regression variants. Everything is integer maths from a SplitMix64 seed: deterministic on every
// host, Linux included.
import GoldenImages

/// SplitMix64: tiny, seedable, the same sequence everywhere.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<bound.
    mutating func next(below bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

enum ImageDiffFixture {
    struct Shapes {
        var rectX: Int
        var rectY: Int
        var rectWidth: Int
        var rectHeight: Int
        var rectVisible = true
        var circleX: Int
        var circleY: Int
        var circleRadius: Int
    }

    static let rectColor: (UInt8, UInt8, UInt8) = (230, 40, 40)
    static let circleColor: (UInt8, UInt8, UInt8) = (40, 200, 230)

    /// The reference layout for a width (128 × 96 or 256 × 192; coordinates scale with width / 128).
    static func shapes(width: Int) -> Shapes {
        let s = width / 128
        return Shapes(rectX: 20 * s, rectY: 20 * s, rectWidth: 24 * s, rectHeight: 18 * s, circleX: 88 * s, circleY: 50 * s,
                      circleRadius: 12 * s)
    }

    /// Gradient background (red across in equal steps: 2 per pixel at 128 wide; green down; blue 80) with the shapes drawn on top.
    static func render(width: Int, height: Int, shapes: Shapes) -> GoldenImage {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let r2 = shapes.circleRadius * shapes.circleRadius
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                var color: (UInt8, UInt8, UInt8) = (UInt8(min(255, x * 256 / width)), UInt8(min(255, y * 256 / height)), 80)
                let dx = x - shapes.circleX, dy = y - shapes.circleY
                if dx * dx + dy * dy <= r2 { color = circleColor }
                if shapes.rectVisible, x >= shapes.rectX, x < shapes.rectX + shapes.rectWidth, y >= shapes.rectY,
                   y < shapes.rectY + shapes.rectHeight {
                    color = rectColor
                }
                rgba[o] = color.0
                rgba[o + 1] = color.1
                rgba[o + 2] = color.2
            }
        }
        return GoldenImage(width: width, height: height, rgba: rgba)!
    }

    static func reference(width: Int = 128, height: Int = 96) -> GoldenImage {
        render(width: width, height: height, shapes: shapes(width: width))
    }

    /// ±`delta` (seeded, per channel, alpha included, clamped) on every pixel.
    static func jitter(_ image: GoldenImage, delta: Int, seed: UInt64) -> GoldenImage {
        var generator = SeededGenerator(seed: seed)
        var rgba = image.rgba
        for i in 0..<rgba.count {
            let offset = generator.next(below: 2 * delta + 1) - delta
            rgba[i] = UInt8(min(255, max(0, Int(rgba[i]) + offset)))
        }
        return GoldenImage(width: image.width, height: image.height, rgba: rgba)!
    }

    /// `count` seeded salt-and-pepper pixels (black or white, opaque), no two within one pixel of each
    /// other, so every noise pixel is its own cluster. Returns the image and the noise positions.
    static func saltAndPepper(_ image: GoldenImage, count: Int, seed: UInt64) -> (image: GoldenImage, positions: [Int]) {
        var generator = SeededGenerator(seed: seed)
        var rgba = image.rgba
        var positions: [Int] = []
        while positions.count < count {
            let x = generator.next(below: image.width), y = generator.next(below: image.height)
            let tooClose = positions.contains { (p: Int) -> Bool in
                abs(p % image.width - x) <= 1 && abs(p / image.width - y) <= 1
            }
            if tooClose { continue }
            let value: UInt8 = generator.next(below: 2) == 0 ? 0 : 255
            let o = (y * image.width + x) * 4
            rgba[o] = value
            rgba[o + 1] = value
            rgba[o + 2] = value
            rgba[o + 3] = 255
            positions.append(y * image.width + x)
        }
        return (GoldenImage(width: image.width, height: image.height, rgba: rgba)!, positions)
    }

    /// The whole image shifted right by `pixels` (left columns repeat the first column).
    static func shiftedRight(_ image: GoldenImage, by pixels: Int) -> GoldenImage {
        var rgba = image.rgba
        for y in 0..<image.height {
            for x in 0..<image.width {
                let source = max(0, x - pixels)
                for c in 0..<4 { rgba[(y * image.width + x) * 4 + c] = image.rgba[(y * image.width + source) * 4 + c] }
            }
        }
        return GoldenImage(width: image.width, height: image.height, rgba: rgba)!
    }

    /// A flat opaque image.
    static func flat(_ width: Int, _ height: Int, value: UInt8 = 100) -> GoldenImage {
        var rgba = [UInt8](repeating: value, count: width * height * 4)
        for p in 0..<(width * height) { rgba[p * 4 + 3] = 255 }
        return GoldenImage(width: width, height: height, rgba: rgba)!
    }

    /// `image` with the red channel of each listed pixel raised by `delta` (clamped).
    static func bumped(_ image: GoldenImage, pixels: [Int], delta: Int) -> GoldenImage {
        var rgba = image.rgba
        for p in pixels { rgba[p * 4] = UInt8(min(255, Int(rgba[p * 4]) + delta)) }
        return GoldenImage(width: image.width, height: image.height, rgba: rgba)!
    }

    /// Pixels of a `w` × `h` block at (x, y) in an image of `width`.
    static func block(x: Int, y: Int, w: Int, h: Int, width: Int) -> [Int] {
        var out: [Int] = []
        for row in y..<(y + h) { for col in x..<(x + w) { out.append(row * width + col) } }
        return out
    }

    /// `count` pixels on a grid of step 3 (never adjacent).
    static func scattered(count: Int, width: Int) -> [Int] {
        let perRow = width / 3
        return (0..<count).map { (i: Int) -> Int in (i / perRow) * 3 * width + (i % perRow) * 3 }
    }
}
