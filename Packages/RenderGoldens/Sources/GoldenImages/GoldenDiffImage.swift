// GoldenDiffImage.swift — the reviewable diff picture of a failed comparison (QA-002-R8; research D8).
// Opaque, the size of the larger image:
// * unchanged pixels: the expected pixel's luminance at 30 % (grey), so the picture stays recognizable;
// * changed within the threshold: yellow;
// * changed above the threshold: red at 128 + 2 × (difference − threshold), capped at 255;
// * outside the overlap of two differently sized images: magenta.

public enum GoldenDiffImage {
    public static let withinColor: (UInt8, UInt8, UInt8) = (255, 220, 0)
    public static let outsideColor: (UInt8, UInt8, UInt8) = (255, 0, 255)

    public static func make(expected: GoldenImage, actual: GoldenImage, tolerance: GoldenTolerance = .qa002) -> GoldenImage {
        let width = max(expected.width, actual.width)
        let height = max(expected.height, actual.height)
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                guard x < expected.width, y < expected.height, x < actual.width, y < actual.height else {
                    out[o] = outsideColor.0
                    out[o + 1] = outsideColor.1
                    out[o + 2] = outsideColor.2
                    continue
                }
                let e = expected.pixel(x: x, y: y)
                let a = actual.pixel(x: x, y: y)
                let dr = abs(Int(e.r) - Int(a.r)), dg = abs(Int(e.g) - Int(a.g))
                let db = abs(Int(e.b) - Int(a.b)), da = abs(Int(e.a) - Int(a.a))
                let d = max(max(dr, dg), max(db, da))
                if d == 0 {
                    let lumaSum: Int = 54 * Int(e.r) + 183 * Int(e.g) + 19 * Int(e.b)   // Rec. 709 weights / 256
                    let alphaScaled: Int = lumaSum / 256 * Int(e.a) / 255
                    let grey = UInt8(alphaScaled * 30 / 100)
                    out[o] = grey
                    out[o + 1] = grey
                    out[o + 2] = grey
                } else if d <= tolerance.channelThreshold {
                    out[o] = withinColor.0
                    out[o + 1] = withinColor.1
                    out[o + 2] = withinColor.2
                } else {
                    let scaled: Int = 128 + min(127, (d - tolerance.channelThreshold) * 2)
                    out[o] = UInt8(scaled)
                    out[o + 1] = 0
                    out[o + 2] = 0
                }
            }
        }
        return GoldenImage(width: width, height: height, rgba: out)!
    }
}
