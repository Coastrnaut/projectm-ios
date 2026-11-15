// SHD-008-T10 (US2; SHD-008-R5, S3): a path mask (an L-shaped VectorPath) on a solid opaque layer through the real
// Metal compositor, 96 × 64 output. Pixels are classified independently of the mask code: the output pixel centre
// is mapped to the path's unit square (identity mask transform: the box is the 64 px shorter side, centred), the
// path's even-odd `contains` says inside or outside, and a plain point-to-segment distance gives the distance to
// the outline. Farther than 1.5 px outside → every channel exactly 0; farther than 1.5 px inside → equal to the
// unmasked render; the summed coverage (alpha ÷ the layer's alpha) is within 2 % of the L's area in pixels.
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import Foundation
import Metal
import VisualGenerators
import XCTest

final class LayerPathMaskTests: XCTestCase {
    private static let size = (w: 96, h: 64)
    private static let color = Pixel(0.8, 0.4, 0.2, 1)

    private static let lShape: [VectorPoint] = [VectorPoint(x: 0.1, y: 0.1), VectorPoint(x: 0.5, y: 0.1), VectorPoint(x: 0.5, y: 0.5),
                                                VectorPoint(x: 0.9, y: 0.5), VectorPoint(x: 0.9, y: 0.9), VectorPoint(x: 0.1, y: 0.9)]

    private func render(_ settings: LayerCompositeSettings) throws -> (pixels: [Pixel], compositor: Compositor) {
        let gpu = try GPURig()
        var stack = LayerStack()
        _ = try stack.add(LayerDescriptor(kind: .photo), settings: settings)
        let compositor = try Compositor(device: gpu.device)
        let top = SolidLayer("masked", color: Self.color)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in top }
        let output = try gpu.output(width: Self.size.w, height: Self.size.h)
        for k in 0..<2 { try gpu.frame(compositor, into: output, time: UInt64(k) * 16_666_667) }
        return (try gpu.read(output), compositor)
    }

    /// Distance in pixels from `q` to the path outline (unit-square points scaled by `side`).
    private static func outlineDistance(_ q: VectorPoint, _ points: [VectorPoint], side: Double) -> Double {
        var best: Double = .greatestFiniteMagnitude
        for i in points.indices {
            let a: VectorPoint = points[i]
            let b: VectorPoint = points[(i + 1) % points.count]
            let ex: Double = b.x - a.x, ey: Double = b.y - a.y
            let wx: Double = q.x - a.x, wy: Double = q.y - a.y
            let t: Double = min(max((wx * ex + wy * ey) / (ex * ex + ey * ey), 0), 1)
            let dx: Double = wx - t * ex, dy: Double = wy - t * ey
            best = min(best, (dx * dx + dy * dy).squareRoot())
        }
        return best * side
    }

    func testPathMaskCoverageMatchesThePolygon() throws {
        let path = try VectorPath(Self.lShape)
        let mask = try LayerMask(shape: .path(path))
        let unmasked = try render(LayerCompositeSettings()).pixels
        let (pixels, compositor) = try render(LayerCompositeSettings(mask: mask))
        XCTAssertEqual(compositor.maskedDraws, 1)
        XCTAssertEqual(compositor.blendDraws, 0, "no extra pass")
        let side: Double = Double(min(Self.size.w, Self.size.h))
        var outside = 0, outsideViolations = 0, inside = 0, insideViolations = 0
        var covered: Double = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let k: Int = j * Self.size.w + i
                let px: Double = Double(i) + 0.5 - Double(Self.size.w) / 2
                let py: Double = Double(j) + 0.5 - Double(Self.size.h) / 2
                let q = VectorPoint(x: px / side + 0.5, y: py / side + 0.5)
                let far: Bool = Self.outlineDistance(q, Self.lShape, side: side) > 1.5
                let p: Pixel = pixels[k]
                covered += Double(p.w / Self.color.w)
                guard far else { continue }
                if path.contains(q) {
                    inside += 1
                    if p != unmasked[k] { insideViolations += 1 }
                } else {
                    outside += 1
                    if p != .zero { outsideViolations += 1 }
                }
            }
        }
        let expected: Double = abs(path.area) * side * side
        print("SHD-008 path mask read-back: inside \(inside), outside \(outside), covered \(covered) px, polygon \(expected) px")
        XCTAssertGreaterThan(inside, 1000)
        XCTAssertGreaterThan(outside, 2000)
        XCTAssertEqual(insideViolations, 0, "inside equals the unmasked layer")
        XCTAssertEqual(outsideViolations, 0, "outside is exactly transparent (notch included)")
        XCTAssertEqual(covered, expected, accuracy: expected * 0.02)
    }
}
#endif
