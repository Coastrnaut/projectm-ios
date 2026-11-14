// CMP-008-T07, T08: gradient masks through the real Metal compositor (CMP-008-R3 to R6, R11; S1, S5).
// A solid opaque layer is drawn over transparent into a 160 × 96 rgba16Float output with a gradient; the
// output alpha is the gradient alpha. Acceptance (the row: "Gradient alpha is monotonic between test
// stops"): every pixel along the gradient axis is sampled; between each pair of adjacent stops alpha must
// be non-decreasing where the stop alphas rise and non-increasing where they fall (within 1/255), and every
// sample must match the CPU reference (`LayerGradientGeometry`) within 1/255. Then: rows (linear) and rings
// (radial) are uniform, a gradient times a circle shape, a CMP-005 transform, the screen blend mode, a change
// at apply, and an opt-in GPU-time bench. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import Metal
import XCTest

final class LayerGradientCompositeTests: XCTestCase {
    private static let size = (w: 160, h: 96)
    private static let color = Pixel(0.8, 0.4, 0.2, 1)
    private static let tolerance: Double = 1.0 / 255

    /// Rise, fall, rise, flat: stops at pixel centres of the 160-wide axis ((k + 0.5) / 160).
    private static func testStops() -> [LayerGradientStop] {
        let pairs: [(Double, Double)] = [(16.5, 0.1), (56.5, 0.95), (96.5, 0.2), (136.5, 0.7), (150.5, 0.7)]
        return pairs.map { (p: (Double, Double)) -> LayerGradientStop in LayerGradientStop(position: p.0 / 160, alpha: p.1) }
    }

    static func linear() throws -> LayerGradientMask {
        try LayerGradientMask(kind: .linear(start: LayerPoint(x: 0, y: 0.5), end: LayerPoint(x: 1, y: 0.5)), stops: testStops())
    }

    /// Centre at the left-middle pixel edge, radius = the shorter side (96 px) → t along the row = x / 96.
    static func radial() throws -> LayerGradientMask {
        let pairs: [(Double, Double)] = [(0.1, 1), (0.45, 0.15), (0.8, 0.6), (1.4, 0)]
        let stops: [LayerGradientStop] = pairs.map { (p: (Double, Double)) -> LayerGradientStop in
            LayerGradientStop(position: min(p.0, 1), alpha: p.1)
        }
        return try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0, y: 0.5), radius: 1), stops: stops)
    }

    // MARK: - Rig

    private func render(_ settings: LayerCompositeSettings, backdrop: Pixel? = nil) throws -> (pixels: [Pixel], compositor: Compositor) {
        let gpu = try GPURig()
        var stack = LayerStack()
        if backdrop != nil { try stack.add(LayerDescriptor(kind: LayerKind("cmp008.backdrop"))) }
        try stack.add(LayerDescriptor(kind: .photo), settings: settings)
        let compositor = try Compositor(device: gpu.device)
        let top = SolidLayer("gradient", color: Self.color)
        let below = SolidLayer("backdrop", color: backdrop ?? .zero)
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            entry.descriptor.kind == .photo ? top : below
        }
        let output = try gpu.output(width: Self.size.w, height: Self.size.h)
        for k in 0..<2 { try gpu.frame(compositor, into: output, time: UInt64(k) * 16_666_667) }
        return (try gpu.read(output), compositor)
    }

    // MARK: - The acceptance check

    struct Sweep: CustomStringConvertible {
        var samples = 0, monotonicViolations = 0, referenceViolations = 0
        var worstStep: Double = 0, worstReference: Double = 0
        var first = ""
        var description: String {
            "samples \(samples), monotonic violations \(monotonicViolations) (worst \(String(format: "%.5f", worstStep))), "
                + "reference violations \(referenceViolations) (worst \(String(format: "%.5f", worstReference)))"
        }
    }

    /// Samples alpha at `points` (layer pixel centres in order of increasing t) and checks each segment of
    /// adjacent stops for monotonicity and every sample against the reference.
    private func sweep(_ alphaAt: (Int) -> Double, count: Int, t: (Int) -> Double, reference: (Int) -> Double,
                       stops: [LayerGradientStop]) -> Sweep {
        var r = Sweep()
        var previous: (t: Double, alpha: Double)?
        for k in 0..<count {
            let tk: Double = t(k)
            let alpha: Double = alphaAt(k)
            let expected: Double = reference(k)
            r.samples += 1
            let off: Double = abs(alpha - expected)
            r.worstReference = max(r.worstReference, off)
            if off > Self.tolerance {
                r.referenceViolations += 1
                if r.first.isEmpty { r.first = "sample \(k) t \(tk): \(alpha) vs reference \(expected)" }
            }
            if let prior = previous, let direction = Self.direction(from: prior.t, to: tk, stops: stops) {
                let step: Double = (alpha - prior.alpha) * direction   // ≥ 0 when it moves the stops' way
                r.worstStep = min(r.worstStep, step)
                if step < -Self.tolerance {
                    r.monotonicViolations += 1
                    if r.first.isEmpty { r.first = "sample \(k) t \(tk): \(prior.alpha) → \(alpha) against the segment" }
                }
            }
            previous = (tk, alpha)
        }
        return r
    }

    /// +1 / −1 when t0 and t1 lie in the same segment [pᵢ₋₁, pᵢ] (or both outside the stops: 0 change, +1);
    /// nil when they straddle a stop (each side is checked on its own segment).
    static func direction(from t0: Double, to t1: Double, stops: [LayerGradientStop]) -> Double? {
        guard let first = stops.first, let last = stops.last else { return nil }
        if t1 <= first.position || t0 >= last.position { return 1 }   // clamped: constant
        for k in 1..<stops.count {
            let a: LayerGradientStop = stops[k - 1]
            let b: LayerGradientStop = stops[k]
            if t0 >= a.position && t1 <= b.position && b.position > a.position {
                return b.alpha >= a.alpha ? 1 : -1
            }
        }
        return nil
    }

    private func assertAcceptance(_ r: Sweep, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(r.samples, 96, name, file: file, line: line)
        XCTAssertEqual(r.monotonicViolations, 0, "\(name): \(r.first)", file: file, line: line)
        XCTAssertEqual(r.referenceViolations, 0, "\(name): \(r.first)", file: file, line: line)
    }

    // MARK: - US1 (CMP-008-S1)

    func testLinearGradientIsMonotonicBetweenStopsAndMatchesTheReference() throws {
        let gradient = try Self.linear()
        let (pixels, compositor) = try render(LayerCompositeSettings(gradientMask: gradient))
        XCTAssertEqual(compositor.maskedDraws, 1)
        XCTAssertEqual(compositor.blendDraws, 0, "no extra pass")
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        let row = Self.size.h / 2
        let w = Self.size.w
        let r = sweep({ (i: Int) -> Double in Double(pixels[row * w + i].w) }, count: w,
                      t: { (i: Int) -> Double in g.parameter(x: Double(i) + 0.5, y: Double(row) + 0.5) },
                      reference: { (i: Int) -> Double in g.alpha(x: Double(i) + 0.5, y: Double(row) + 0.5) },
                      stops: gradient.stops)
        assertAcceptance(r, "linear")
        // The stops hold at their positions (they sit on pixel centres).
        for stop in gradient.stops {
            let i = Int((stop.position * Double(w)).rounded(.down))
            XCTAssertEqual(Double(pixels[row * w + i].w), stop.alpha, accuracy: Self.tolerance, "stop at \(stop.position)")
        }
        // A horizontal gradient is the same on every row; colour is premultiplied by the same alpha.
        var rowViolations = 0
        for j in 0..<Self.size.h where j != row {
            for i in 0..<w where pixels[j * w + i] != pixels[row * w + i] { rowViolations += 1 }
        }
        XCTAssertEqual(rowViolations, 0)
        let mid: Pixel = pixels[row * w + 76]
        XCTAssertEqual(mid.x, Self.color.x * mid.w, accuracy: 0.002)
        print("CMP-008 linear read-back (160 × 96, row \(row)): \(r)")
    }

    func testRadialGradientIsMonotonicAlongARayAndRound() throws {
        let gradient = try Self.radial()
        let (pixels, _) = try render(LayerCompositeSettings(gradientMask: gradient))
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        let w = Self.size.w
        let row = Self.size.h / 2
        let r = sweep({ (i: Int) -> Double in Double(pixels[row * w + i].w) }, count: w,
                      t: { (i: Int) -> Double in g.parameter(x: Double(i) + 0.5, y: Double(row) + 0.5) },
                      reference: { (i: Int) -> Double in g.alpha(x: Double(i) + 0.5, y: Double(row) + 0.5) },
                      stops: gradient.stops)
        assertAcceptance(r, "radial ray")
        // Every pixel matches the reference (so equal distance gives equal alpha: round).
        var off = 0
        for j in 0..<Self.size.h {
            for i in 0..<w {
                let expected: Double = g.alpha(x: Double(i) + 0.5, y: Double(j) + 0.5)
                if abs(Double(pixels[j * w + i].w) - expected) > Self.tolerance { off += 1 }
            }
        }
        XCTAssertEqual(off, 0, "whole picture vs reference")
        print("CMP-008 radial read-back (160 × 96, ray right from the centre): \(r)")
    }

    func testAllOpaqueStopsDrawExactlyLikeNoGradient() throws {
        let plain = try render(LayerCompositeSettings()).pixels
        let opaque = try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.3),
                                           stops: [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 1, alpha: 1)])
        XCTAssertEqual(try render(LayerCompositeSettings(gradientMask: opaque)).pixels, plain)
    }

    // MARK: - Composition (CMP-008-R5)

    func testGradientTimesShapeKeepsOutsideExactlyTransparent() throws {
        let gradient = try Self.linear()
        let circle = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.6, y: 0.6)))
        let (pixels, compositor) = try render(LayerCompositeSettings(mask: circle, gradientMask: gradient))
        XCTAssertEqual(compositor.maskedDraws, 1)
        let shape = circle.geometry(width: Self.size.w, height: Self.size.h)
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        var outside = 0, outsideViolations = 0, worst: Double = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let x: Double = Double(i) + 0.5, y: Double = Double(j) + 0.5
                let p: Pixel = pixels[j * Self.size.w + i]
                if shape.signedDistance(x: x, y: y) >= shape.band / 2 + 0.05 {
                    outside += 1
                    if p != .zero { outsideViolations += 1 }
                    continue
                }
                let expected: Double = shape.coverage(x: x, y: y) * g.alpha(x: x, y: y)
                worst = max(worst, abs(Double(p.w) - expected))
            }
        }
        XCTAssertGreaterThan(outside, 100)
        XCTAssertEqual(outsideViolations, 0)
        XCTAssertLessThanOrEqual(worst, 0.01)
    }

    func testTheGradientMovesWithTheLayerTransform() throws {
        let transform = try LayerTransform(translation: LayerPoint(x: 0.15, y: 0), uniformScale: 0.9, rotation: 0.3)
        let gradient = try Self.linear()
        let (pixels, _) = try render(LayerCompositeSettings(transform: transform, gradientMask: gradient))
        let inverse = try XCTUnwrap(transform.matrix(outputWidth: Self.size.w, outputHeight: Self.size.h).inverse)
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        let w: Double = Double(Self.size.w), h: Double = Double(Self.size.h)
        var compared = 0, worst: Double = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let q = inverse.apply(LayerPoint(x: (Double(i) + 0.5) / w, y: (Double(j) + 0.5) / h))
                let lx: Double = q.x * w, ly: Double = q.y * h
                // Stay clear of the picture's edge, where bilinear sampling fades to transparent.
                guard lx > 2, lx < w - 2, ly > 2, ly < h - 2 else { continue }
                compared += 1
                worst = max(worst, abs(Double(pixels[j * Self.size.w + i].w) - g.alpha(x: lx, y: ly)))
            }
        }
        XCTAssertGreaterThan(compared, 5_000)
        XCTAssertLessThanOrEqual(worst, 0.01, "reference at the inverse-mapped layer pixel")
    }

    func testABlendModeLayerTakesTheGradientInItsOwnPass() throws {
        let gradient = try Self.linear()
        let (pixels, compositor) = try render(LayerCompositeSettings(blendMode: .screen, gradientMask: gradient))
        XCTAssertEqual(compositor.blendDraws, 1)
        XCTAssertEqual(compositor.maskedDraws, 0)
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        let row = Self.size.h / 2
        let w = Self.size.w
        let r = sweep({ (i: Int) -> Double in Double(pixels[row * w + i].w) }, count: w,
                      t: { (i: Int) -> Double in g.parameter(x: Double(i) + 0.5, y: Double(row) + 0.5) },
                      reference: { (i: Int) -> Double in g.alpha(x: Double(i) + 0.5, y: Double(row) + 0.5) },
                      stops: gradient.stops)
        assertAcceptance(r, "screen")
    }

    func testAGradientChangeAtApplyShowsNextFrameWithoutRecreatingAnything() throws {
        let gpu = try GPURig()
        var stack = LayerStack()
        let id = try stack.add(LayerDescriptor(kind: .photo), settings: LayerCompositeSettings(gradientMask: .linearDefault))
        let compositor = try Compositor(device: gpu.device)
        let layer = SolidLayer("gradient", color: Self.color)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in layer }
        let output = try gpu.output(width: Self.size.w, height: Self.size.h)
        for k in 0..<2 { try gpu.frame(compositor, into: output, time: UInt64(k) * 16_666_667) }
        let pictures = compositor.pictureAllocations
        let preparations = compositor.layerPreparations
        try stack.setSettings(LayerCompositeSettings(gradientMask: try Self.radial()), of: id)
        var calls = 0
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            return SolidLayer("unexpected", color: .zero)
        }
        XCTAssertEqual(calls, 0, "no layer re-created")
        compositor.resetFlashHistory()
        try gpu.frame(compositor, into: output, time: 100_000_000)
        XCTAssertEqual(try gpu.read(output), try render(LayerCompositeSettings(gradientMask: try Self.radial())).pixels,
                       "the new gradient on the first frame")
        XCTAssertEqual(compositor.pictureAllocations, pictures)
        XCTAssertEqual(compositor.layerPreparations, preparations)
        try stack.setSettings(LayerCompositeSettings(), of: id)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in SolidLayer("unexpected", color: .zero) }
        compositor.resetFlashHistory()
        try gpu.frame(compositor, into: output, time: 200_000_000)
        XCTAssertEqual(compositor.maskedDraws, 0)
        XCTAssertEqual(try gpu.read(output), try render(LayerCompositeSettings()).pixels, "no gradient again, bit for bit")
    }

    // MARK: - GPU time (CMP-008-S5; opt-in, not asserted)

    func testGradientGPUTimeBench() throws {
        guard ProcessInfo.processInfo.environment["CMP008_BENCH"] == "1" else {
            throw XCTSkip("Set CMP008_BENCH=1 to measure GPU time of a full-screen gradient layer (Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        let eight: [LayerGradientStop] = (0..<8).map { (k: Int) -> LayerGradientStop in
            LayerGradientStop(position: Double(k) / 7, alpha: k % 2 == 0 ? 1 : 0.2)
        }
        let cases: [(String, LayerCompositeSettings)] = [
            ("no gradient", LayerCompositeSettings()),
            ("linear, 5 stops", LayerCompositeSettings(gradientMask: try Self.linear())),
            ("radial, 8 stops", LayerCompositeSettings(gradientMask: try LayerGradientMask(
                kind: .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.8), stops: eight))),
            ("radial 8 stops × circle", LayerCompositeSettings(mask: try LayerMask(shape: .ellipse, feather: 0.05),
                                                               gradientMask: try LayerGradientMask(
                kind: .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.8), stops: eight))),
        ]
        var lines: [String] = []
        for (name, settings) in cases {
            var stack = LayerStack()
            try stack.add(LayerDescriptor(kind: .photo), settings: settings)
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
                if k >= 10 { samples.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
            }
            samples.sort()
            let median: Double = samples[samples.count / 2]
            let p95: Double = samples[samples.count * 95 / 100]
            lines.append("| \(name) | " + String(format: "%.3f | %.3f", median, p95) + " |")
        }
        print("CMP-008 GPU time per frame, 1920 × 1080 (ms): | case | median | p95 |")
        for line in lines { print("CMP-008 bench: " + line) }
    }
}
#endif
