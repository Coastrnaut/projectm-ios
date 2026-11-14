// GoldenDiffImage.swift — the reviewable diff picture of a comparison (QA-002-R8; research D8;
// QA-003 contract I3). Opaque, the size of the larger image:
// * unchanged pixels: the expected pixel's luminance at 30 % (grey), so the picture stays recognizable;
// * changed within the threshold: yellow;
// * above the threshold but forgiven as a one-pixel shift (QA-003): orange;
// * above the threshold and unmatched: red at 128 + 2 × (difference − threshold), capped at 255;
// * outside the overlap of two differently sized images: magenta;
// * the bounding box of the differences (QA-003): a cyan outline drawn over grey pixels only.

public enum GoldenDiffImage {
    public static let withinColor: (UInt8, UInt8, UInt8) = (255, 220, 0)
    public static let forgivenColor: (UInt8, UInt8, UInt8) = (255, 140, 0)
    public static let outsideColor: (UInt8, UInt8, UInt8) = (255, 0, 255)
    public static let boxColor: (UInt8, UInt8, UInt8) = (0, 255, 255)

    public static func make(expected: GoldenImage, actual: GoldenImage, tolerance: GoldenTolerance = .golden) -> GoldenImage {
        let width = max(expected.width, actual.width)
        let height = max(expected.height, actual.height)
        let analysis = ImageDiff.analyze(expected: expected, actual: actual, tolerance: tolerance)
        let classes = analysis.classes
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                guard x < expected.width, y < expected.height, x < actual.width, y < actual.height else {
                    set(&out, o, outsideColor)
                    continue
                }
                let e = expected.pixel(x: x, y: y)
                switch classes.isEmpty ? .unchanged : classes[y * expected.width + x] {
                case .unchanged:
                    let lumaSum: Int = 54 * Int(e.r) + 183 * Int(e.g) + 19 * Int(e.b)   // Rec. 709 weights / 256
                    let alphaScaled: Int = lumaSum / 256 * Int(e.a) / 255
                    let grey = UInt8(alphaScaled * 30 / 100)
                    set(&out, o, (grey, grey, grey))
                case .withinTolerance:
                    set(&out, o, withinColor)
                case .forgiven:
                    set(&out, o, forgivenColor)
                case .unmatched:
                    let a = actual.pixel(x: x, y: y)
                    let dr = abs(Int(e.r) - Int(a.r)), dg = abs(Int(e.g) - Int(a.g))
                    let db = abs(Int(e.b) - Int(a.b)), da = abs(Int(e.a) - Int(a.a))
                    let d = max(max(dr, dg), max(db, da))
                    let scaled: Int = 128 + min(127, (d - tolerance.channelThreshold) * 2)
                    set(&out, o, (UInt8(scaled), 0, 0))
                }
            }
        }
        if let box = analysis.report.boundingBox {
            outline(&out, width: width, box: box, classes: classes, classWidth: expected.width)
        }
        return GoldenImage(width: width, height: height, rgba: out)!
    }

    private static func set(_ out: inout [UInt8], _ o: Int, _ color: (UInt8, UInt8, UInt8)) {
        out[o] = color.0
        out[o + 1] = color.1
        out[o + 2] = color.2
    }

    /// Cyan one pixel outside the box (clamped to the image), only over unchanged pixels.
    private static func outline(_ out: inout [UInt8], width: Int, box: ImageDiffBoundingBox, classes: [ImageDiff.PixelClass],
                                classWidth: Int) {
        let height = out.count / 4 / width
        let x0 = max(0, box.minX - 1), x1 = min(width - 1, box.maxX + 1)
        let y0 = max(0, box.minY - 1), y1 = min(height - 1, box.maxY + 1)
        for y in y0...y1 {
            for x in x0...x1 where x == x0 || x == x1 || y == y0 || y == y1 {
                let p = y * classWidth + x
                guard p < classes.count, classes[p] == .unchanged else { continue }
                set(&out, (y * width + x) * 4, boxColor)
            }
        }
    }
}
