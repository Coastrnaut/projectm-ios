// CMP-007-T07, T09, T10: shape masks through the real Metal compositor (CMP-007-R3, R4, R6, R7, R12,
// S1-S3, S5). A solid opaque layer is drawn over transparent into a 96 × 64 output, once unmasked and
// once masked; every output pixel is classified with the CPU reference (`LayerMaskGeometry`) at its
// layer pixel:
//   outside (distance ≥ band/2 + 0.05 px; inverted: ≤ −band/2 − 0.05) → all channels exactly 0;
//   inside  (the opposite side)                                     → bit-equal to the unmasked render;
//   edge    (the rest)                                              → |alpha − coverage · unmasked alpha| ≤ 0.01.
// The 0.05 px margin covers CPU (Double) vs GPU (float) rounding at the band's outer edge (research
// CMP-007-D7). Then: a CMP-005 transform, a CMP-006 fit photo, the screen blend mode (alone and over a
// backdrop), opacity, a mask change at apply, the no-extra-pass rule, and an opt-in GPU-time bench.
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import Foundation
import ImageLayer
import Metal
import XCTest

final class LayerMaskCompositeTests: XCTestCase {
    private static let size = (w: 96, h: 64)
    private static let color = Pixel(0.8, 0.4, 0.2, 1)
    private static let solidKind = LayerKind("cmp007.solid")
    private static let margin: Double = 0.05

    // MARK: - Shapes under test

    private static func shapes() throws -> [(String, LayerMask)] {
        var hexagon: [LayerPoint] = []
        for k in 0..<6 {
            let a: Double = Double(k) * Double.pi / 3
            hexagon.append(LayerPoint(x: 0.5 * cos(a), y: 0.5 * sin(a)))
        }
        let l: [LayerPoint] = [LayerPoint(x: -0.5, y: -0.5), LayerPoint(x: 0, y: -0.5), LayerPoint(x: 0, y: 0),
                               LayerPoint(x: 0.5, y: 0), LayerPoint(x: 0.5, y: 0.5), LayerPoint(x: -0.5, y: 0.5)]
        return [
            ("circle", try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.6, y: 0.6)))),
            ("rounded rectangle", try LayerMask(shape: .rectangle(cornerRadius: 0.25),
                                                transform: LayerMaskTransform(scale: LayerPoint(x: 1, y: 0.6), rotation: 0.3))),
            ("convex polygon", try LayerMask(shape: .polygon(hexagon),
                                             transform: LayerMaskTransform(center: LayerPoint(x: 0.45, y: 0.55),
                                                                           scale: LayerPoint(x: 0.8, y: 0.8)))),
            ("concave polygon", try LayerMask(shape: .polygon(l),
                                              transform: LayerMaskTransform(scale: LayerPoint(x: 0.8, y: 0.8), rotation: -0.2))),
            ("inverted circle", try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.6, y: 0.6)),
                                              inverted: true)),
            ("feathered ellipse", try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 1.2, y: 0.6)),
                                                feather: 0.1)),
        ]
    }

    // MARK: - Rig

    private struct Rig {
        let gpu: GPURig
        let compositor: Compositor
        var stack: LayerStack
        let id: LayerInstanceID
        var factoryCalls = 0
    }

    private func makeRig(_ settings: LayerCompositeSettings, color: Pixel = LayerMaskCompositeTests.color,
                         backdrop: Pixel? = nil, layer: (any LayerSource)? = nil) throws -> Rig {
        let gpu = try GPURig()
        var stack = LayerStack()
        if backdrop != nil { try stack.add(LayerDescriptor(kind: Self.solidKind)) }
        let id = try stack.add(LayerDescriptor(kind: .photo), settings: settings)
        let compositor = try Compositor(device: gpu.device)
        let top: any LayerSource = layer ?? SolidLayer("masked", color: color)
        let below = SolidLayer("backdrop", color: backdrop ?? .zero)
        var calls = 0
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            return entry.descriptor.kind == .photo ? top : below
        }
        return Rig(gpu: gpu, compositor: compositor, stack: stack, id: id, factoryCalls: calls)
    }

    private func render(_ rig: Rig, startTime: UInt64 = 0) throws -> [Pixel] {
        let output = try rig.gpu.output(width: Self.size.w, height: Self.size.h)
        for k in 0..<2 { try rig.gpu.frame(rig.compositor, into: output, time: startTime + UInt64(k) * 16_666_667) }
        return try rig.gpu.read(output)
    }

    private func render(_ settings: LayerCompositeSettings, backdrop: Pixel? = nil,
                        layer: (any LayerSource)? = nil) throws -> (pixels: [Pixel], rig: Rig) {
        let rig = try makeRig(settings, backdrop: backdrop, layer: layer)
        return (try render(rig), rig)
    }

    // MARK: - Checking against the reference

    struct Result: CustomStringConvertible {
        var outside = 0, outsideViolations = 0, inside = 0, insideViolations = 0, edge = 0
        var edgeMaxError: Float = 0
        var first = ""
        var description: String {
            "outside \(outside) (violations \(outsideViolations)), inside \(inside) (violations \(insideViolations)), "
                + "edge \(edge) (max error \(String(format: "%.4f", edgeMaxError)))"
        }
    }

    /// `layerPixel` maps an output pixel centre (pixels) to the layer pixel the compositor evaluates.
    private func check(_ masked: [Pixel], unmasked: [Pixel], mask: LayerMask,
                       layerPixel: (Double, Double) -> (Double, Double) = { ($0, $1) },
                       outsideValue: (Int) -> Pixel = { _ in .zero }) -> Result {
        let g = mask.geometry(width: Self.size.w, height: Self.size.h)
        let half: Double = g.band / 2 + Self.margin
        var r = Result()
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let k: Int = j * Self.size.w + i
                let (lx, ly) = layerPixel(Double(i) + 0.5, Double(j) + 0.5)
                let d: Double = g.signedDistance(x: lx, y: ly)
                let isOutside: Bool = mask.inverted ? d <= -half : d >= half
                let isInside: Bool = mask.inverted ? d >= half : d <= -half
                let p: Pixel = masked[k]
                if isOutside {
                    r.outside += 1
                    if p != outsideValue(k) {
                        r.outsideViolations += 1
                        if r.first.isEmpty { r.first = "outside (\(i), \(j)) d \(d): \(p)" }
                    }
                } else if isInside {
                    r.inside += 1
                    if p != unmasked[k] {
                        r.insideViolations += 1
                        if r.first.isEmpty { r.first = "inside (\(i), \(j)) d \(d): \(p) vs \(unmasked[k])" }
                    }
                } else {
                    r.edge += 1
                    let coverage: Float = Float(g.coverage(x: lx, y: ly))
                    let expected: Float = coverage * unmasked[k].w
                    let error: Float = abs(p.w - expected)
                    r.edgeMaxError = max(r.edgeMaxError, error)
                    if p.w < 0 { r.edgeMaxError = .infinity }
                }
            }
        }
        return r
    }

    private func assertClean(_ r: Result, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(r.outside, 100, "\(name): enough outside pixels", file: file, line: line)
        XCTAssertGreaterThan(r.inside, 100, "\(name): enough inside pixels", file: file, line: line)
        XCTAssertEqual(r.outsideViolations, 0, "\(name): \(r.first)", file: file, line: line)
        XCTAssertEqual(r.insideViolations, 0, "\(name): \(r.first)", file: file, line: line)
        XCTAssertLessThanOrEqual(r.edgeMaxError, 0.01, "\(name): \(r)", file: file, line: line)
    }

    // MARK: - US1: each shape (CMP-007-S1, S2)

    func testEveryShapeIsExactlyTransparentOutsideAndUnchangedInside() throws {
        let unmasked = try render(LayerCompositeSettings()).pixels
        assertAll(unmasked, equal: Self.color, tolerance: 0.001, "unmasked solid")
        var table: [String] = []
        for (name, mask) in try Self.shapes() {
            let (pixels, rig) = try render(LayerCompositeSettings(mask: mask))
            XCTAssertEqual(rig.compositor.maskedDraws, 1, name)
            XCTAssertEqual(rig.compositor.blendDraws, 0, "\(name): no extra pass")
            let r = check(pixels, unmasked: unmasked, mask: mask)
            assertClean(r, name)
            table.append("| \(name) | \(r.outside) | \(r.outsideViolations) | \(r.inside) | \(r.insideViolations) | \(r.edge) | "
                         + String(format: "%.4f", r.edgeMaxError) + " |")
        }
        print("CMP-007 read-back (96 × 64): | shape | outside | outside alpha ≠ 0 | inside | inside ≠ unmasked | edge | edge max error |")
        for line in table { print("CMP-007 read-back: " + line) }
    }

    // MARK: - US2: composition (CMP-007-S3, R6, R7, R12)

    func testTheMaskMovesWithTheLayerTransform() throws {
        let transform = try LayerTransform(translation: LayerPoint(x: 0.2, y: -0.1), uniformScale: 0.8, rotation: 0.4)
        let mask = try Self.shapes()[3].1   // the concave polygon
        let unmasked = try render(LayerCompositeSettings(transform: transform)).pixels
        let (pixels, rig) = try render(LayerCompositeSettings(transform: transform, mask: mask))
        XCTAssertEqual(rig.compositor.maskedDraws, 1)
        let inverse = try XCTUnwrap(transform.matrix(outputWidth: Self.size.w, outputHeight: Self.size.h).inverse)
        let w: Double = Double(Self.size.w), h: Double = Double(Self.size.h)
        let r = check(pixels, unmasked: unmasked, mask: mask) { (x: Double, y: Double) -> (Double, Double) in
            let q = inverse.apply(LayerPoint(x: x / w, y: y / h))
            return (q.x * w, q.y * h)
        }
        assertClean(r, "transformed")
        // The shape really moved: the untransformed reference disagrees somewhere.
        let unmoved = check(pixels, unmasked: unmasked, mask: mask)
        XCTAssertGreaterThan(unmoved.outsideViolations + unmoved.insideViolations, 0)
    }

    func testAMaskedFitPhotoIsCutByTheLayerRectangle() throws {
        let gpu = try GPURig()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CMP007-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = ImageFixtures.image(width: 30, height: 60) { (_: Int, _: Int) -> ImageFixtures.RGBA in
            ImageFixtures.RGBA(r: 255, g: 128, b: 0, a: 255)
        }
        let url = directory.appendingPathComponent("portrait.png")
        try ImageFixtures.encode(image, .png).write(to: url)
        func photo() -> ImageLayerSource {
            let p = ImageLayerSource(device: gpu.device)
            p.content = .file(url)
            p.waitUntilLoaded()
            return p
        }
        // A wide ellipse larger than the fitted content: bars inside it stay transparent; the mask is
        // centred on the layer (not on the content rectangle).
        let mask = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 1.2, y: 0.8)))
        let fit = LayerFit(mode: .fit)
        let unmasked = try render(LayerCompositeSettings(fit: fit), layer: photo()).pixels
        let (pixels, _) = try render(LayerCompositeSettings(fit: fit, mask: mask), layer: photo())
        // The fitted content covers 32 of 96 columns (bars transparent in both renders).
        XCTAssertEqual(unmasked[32 * Self.size.w + 2].w, 0, "fit bar")
        XCTAssertEqual(unmasked[32 * Self.size.w + 48].w, 1, accuracy: 0.001, "content")
        let r = check(pixels, unmasked: unmasked, mask: mask)
        XCTAssertEqual(r.outsideViolations, 0, r.first)
        XCTAssertEqual(r.insideViolations, 0, r.first)
        XCTAssertLessThanOrEqual(r.edgeMaxError, 0.01, "\(r)")
        XCTAssertEqual(pixels[2 * Self.size.w + 48], .zero, "content above the ellipse is cut")
    }

    func testABlendModeLayerIsMaskedInItsOwnPass() throws {
        let mask = try Self.shapes()[0].1
        // Screen over nothing: the composite is the masked source, so outside is exactly transparent.
        let unmasked = try render(LayerCompositeSettings(blendMode: .screen)).pixels
        let (pixels, rig) = try render(LayerCompositeSettings(blendMode: .screen, mask: mask))
        XCTAssertEqual(rig.compositor.blendDraws, 1)
        XCTAssertEqual(rig.compositor.maskedDraws, 0, "blend layers are masked inside cmp_blend")
        assertClean(check(pixels, unmasked: unmasked, mask: mask), "screen alone")
        // Screen over a backdrop: outside, the backdrop is untouched; inside, the unmasked screen result.
        let backdrop = Pixel(0.1, 0.3, 0.5, 1)
        let below = try render(LayerCompositeSettings(), layer: SolidLayer("backdrop only", color: backdrop)).pixels
        let screened = try render(LayerCompositeSettings(blendMode: .screen), backdrop: backdrop).pixels
        let masked = try render(LayerCompositeSettings(blendMode: .screen, mask: mask), backdrop: backdrop).pixels
        let r = check(masked, unmasked: screened, mask: mask, outsideValue: { (k: Int) -> Pixel in below[k] })
        XCTAssertEqual(r.outsideViolations, 0, r.first)
        XCTAssertEqual(r.insideViolations, 0, r.first)
        XCTAssertGreaterThan(r.inside, 100)
    }

    func testOpacityAndCoverageMultiply() throws {
        let mask = try Self.shapes()[5].1   // feathered ellipse
        let unmasked = try render(LayerCompositeSettings(opacity: 0.5)).pixels
        let (pixels, _) = try render(LayerCompositeSettings(opacity: 0.5, mask: mask))
        assertClean(check(pixels, unmasked: unmasked, mask: mask), "opacity 0.5")
    }

    func testAMaskChangeAtApplyShowsNextFrameWithoutRecreatingAnything() throws {
        let shapes = try Self.shapes()
        var rig = try makeRig(LayerCompositeSettings(mask: shapes[0].1))
        let unmasked = try render(LayerCompositeSettings()).pixels
        assertClean(check(try render(rig), unmasked: unmasked, mask: shapes[0].1), "before")
        let pictures = rig.compositor.pictureAllocations
        let preparations = rig.compositor.layerPreparations
        let moved = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(center: LayerPoint(x: 0.3, y: 0.6),
                                                                                  scale: LayerPoint(x: 0.5, y: 0.5)))
        try rig.stack.setSettings(LayerCompositeSettings(mask: moved), of: rig.id)
        var calls = 0
        try rig.compositor.apply(rig.stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            return SolidLayer("unexpected", color: .zero)
        }
        XCTAssertEqual(calls, 0, "no layer re-created")
        XCTAssertEqual(rig.compositor.shownMask(ofLayer: 0), moved)
        rig.compositor.resetFlashHistory()   // a deliberate jump (FX-019)
        let output = try rig.gpu.output(width: Self.size.w, height: Self.size.h)
        try rig.gpu.frame(rig.compositor, into: output, time: 100_000_000)
        assertClean(check(try rig.gpu.read(output), unmasked: unmasked, mask: moved), "after, first frame")
        XCTAssertEqual(rig.compositor.pictureAllocations, pictures, "no new pictures")
        XCTAssertEqual(rig.compositor.layerPreparations, preparations, "no new prepare")
        // Removing the mask goes back to the plain path.
        try rig.stack.setSettings(LayerCompositeSettings(), of: rig.id)
        try rig.compositor.apply(rig.stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            SolidLayer("unexpected", color: .zero)
        }
        rig.compositor.resetFlashHistory()
        try rig.gpu.frame(rig.compositor, into: output, time: 200_000_000)
        XCTAssertEqual(rig.compositor.maskedDraws, 0)
        XCTAssertEqual(try rig.gpu.read(output), unmasked, "unmasked again, bit for bit")
    }

    // MARK: - GPU time (CMP-007-S5; opt-in, not asserted)

    func testBenchMaskedFullScreenLayer() throws {
        guard ProcessInfo.processInfo.environment["CMP007_BENCH"] == "1" else {
            throw XCTSkip("Set CMP007_BENCH=1 to measure GPU time per shape (Release, Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        var cases: [(String, LayerMask?)] = [("unmasked", nil)]
        for (name, mask) in try Self.shapes() { cases.append((name, mask)) }
        var many: [LayerPoint] = []
        for k in 0..<32 {
            let a: Double = Double(k) * 2 * Double.pi / 32
            let r: Double = k % 2 == 0 ? 0.5 : 0.3
            many.append(LayerPoint(x: r * cos(a), y: r * sin(a)))
        }
        cases.append(("32-point polygon", try LayerMask(shape: .polygon(many), feather: 0.02)))
        var lines: [String] = []
        for (name, mask) in cases {
            var stack = LayerStack()
            try stack.add(LayerDescriptor(kind: Self.solidKind), settings: LayerCompositeSettings(mask: mask))
            let compositor = try Compositor(device: gpu.device)
            let layer = SolidLayer("bench", color: Self.color)
            try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in layer }
            var samples: [Double] = []
            for k in 0..<130 {
                let commands = try XCTUnwrap(gpu.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: UInt64(k) * 16_666_667,
                                         contentScale: 2, reduceFlashing: false, audio: .empty)
                commands.commit()
                commands.waitUntilCompleted()
                let gpuSeconds: Double = commands.gpuEndTime - commands.gpuStartTime
                if k >= 10 { samples.append(gpuSeconds * 1000) }
            }
            samples.sort()
            let median: Double = samples[samples.count / 2]
            let p95: Double = samples[samples.count * 95 / 100]
            lines.append("| \(name) | " + String(format: "%.3f | %.3f", median, p95) + " |")
        }
        print("CMP-007 GPU time per frame, 1920 × 1080 (ms): | case | median | p95 |")
        for line in lines { print("CMP-007 bench: " + line) }
    }
}
#endif
