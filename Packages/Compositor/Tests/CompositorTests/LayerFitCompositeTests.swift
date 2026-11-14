// CMP-006-T08, T10, T11: aspect fitting through the real Metal compositor (CMP-006-R7, R8, R11, S3,
// S5). A portrait marker photo (24 × 40: a yellow top band, then red / green / blue / white quadrants)
// is drawn through a stack entry's fit into a portrait (72 × 144) and then a landscape (128 × 72)
// output by the same compositor. Every output pixel whose content coordinate is not next to a marker
// edge is compared with the colour `LayerFitPlacement` predicts (transparent outside the content);
// nothing is judged by eye. Plus: a non-normal blend mode, a CMP-005 transform, a fit change at
// apply, a layer without fitting, a rotated portrait video in fit, and a GPU-time bench (opt-in).
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO) && canImport(AVFoundation)
import Compositor
import Foundation
import ImageLayer
import Metal
import VideoLayer
import XCTest

final class LayerFitCompositeTests: XCTestCase {
    private typealias RGBA = ImageFixtures.RGBA
    private var directory: URL!
    private static let photoWidth = 24
    private static let photoHeight = 40
    private static let portrait = (w: 72, h: 144)
    private static let landscape = (w: 128, h: 72)
    private static let solidKind = LayerKind("cmp006.solid")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CMP006-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The marker photo

    /// Linear premultiplied colour of content pixel coordinate (x, y) (in content pixels).
    private static func marker(x: Double, y: Double) -> Pixel {
        if y < 4 { return Pixel(1, 1, 0, 1) }                        // top band: yellow
        let left: Bool = x < 12
        let top: Bool = y < 22
        if top { return left ? Pixel(1, 0, 0, 1) : Pixel(0, 1, 0, 1) }  // red | green
        return left ? Pixel(0, 0, 1, 1) : Pixel(1, 1, 1, 1)           // blue | white
    }

    private static let edgesX: [Double] = [0, 12, 24]
    private static let edgesY: [Double] = [0, 4, 22, 40]

    private func photoURL() throws -> URL {
        let image = ImageFixtures.image(width: Self.photoWidth, height: Self.photoHeight) { x, y in
            let p = Self.marker(x: Double(x) + 0.5, y: Double(y) + 0.5)
            return RGBA(r: UInt8(p.x * 255), g: UInt8(p.y * 255), b: UInt8(p.z * 255), a: 255)
        }
        let url = directory.appendingPathComponent("marker.png")
        try ImageFixtures.encode(image, .png).write(to: url)
        return url
    }

    private struct Rig {
        let gpu: GPURig
        let photo: ImageLayerSource
        let compositor: Compositor
        var stack: LayerStack
        let photoID: LayerInstanceID
        var factoryCalls = 0
    }

    /// A compositor with an optional solid backdrop (bottom) and the photo, applied from a stack.
    private func makeRig(fit: LayerFit?, blend: LayerBlendMode = .normal, transform: LayerTransform = .identity,
                         backdrop: Pixel? = nil) throws -> Rig {
        let gpu = try GPURig()
        let photo = ImageLayerSource(device: gpu.device)
        photo.content = .file(try photoURL())
        photo.waitUntilLoaded()
        XCTAssertEqual(photo.state, .ready(width: Self.photoWidth, height: Self.photoHeight))
        let solid = SolidLayer("backdrop", color: backdrop ?? Pixel(0, 0, 0, 0))
        var stack = LayerStack()
        if backdrop != nil { try stack.add(LayerDescriptor(kind: Self.solidKind)) }
        let id = try stack.add(LayerDescriptor(kind: .photo),
                               settings: LayerCompositeSettings(blendMode: blend, transform: transform, fit: fit))
        let compositor = try Compositor(device: gpu.device)
        var rig = Rig(gpu: gpu, photo: photo, compositor: compositor, stack: stack, photoID: id)
        var calls = 0
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            return entry.descriptor.kind == .photo ? photo : solid
        }
        rig.factoryCalls = calls
        return rig
    }

    /// Renders three frames into a new output of `size` and reads the last one.
    private func render(_ rig: Rig, _ size: (w: Int, h: Int), startTime: UInt64) throws -> [Pixel] {
        let output = try rig.gpu.output(width: size.w, height: size.h)
        for k in 0..<3 { try rig.gpu.frame(rig.compositor, into: output, time: startTime + UInt64(k) * 16_666_667) }
        XCTAssertEqual(rig.compositor.lastFlashGain, 1, "no flash limiting on a still photo")
        return try rig.gpu.read(output)
    }

    private struct Check { var compared = 0; var transparent = 0; var failures = 0; var first = "" }

    /// Compares every output pixel whose content coordinate is at least `margin` content pixels from a
    /// marker or content edge with the predicted colour. `place` maps an output point (0…1) to a
    /// layer-picture point (identity without a transform; nil: outside the picture).
    private func check(_ pixels: [Pixel], _ size: (w: Int, h: Int), _ placement: LayerFitPlacement, margin: Double,
                       place: (LayerPoint) -> LayerPoint? = { $0 }, expect: (Pixel) -> Pixel = { $0 }) -> Check {
        var result = Check()
        let w: Double = Double(Self.photoWidth), h: Double = Double(Self.photoHeight)
        for j in 0..<size.h {
            for i in 0..<size.w {
                let q = LayerPoint(x: (Double(i) + 0.5) / Double(size.w), y: (Double(j) + 0.5) / Double(size.h))
                var predicted = Pixel(0, 0, 0, 0)
                if let p = place(q) {
                    let pictureMargin: Double = 1.5
                    let px: Double = p.x * Double(size.w), py: Double = p.y * Double(size.h)
                    let nearX: Bool = abs(px) < pictureMargin || abs(px - Double(size.w)) < pictureMargin
                    let nearY: Bool = abs(py) < pictureMargin || abs(py - Double(size.h)) < pictureMargin
                    if nearX || nearY { continue }   // next to the picture's own edge
                    if p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 {
                        let t = placement.textureCoordinate(x: p.x, y: p.y)
                        let cx: Double = t.x * w, cy: Double = t.y * h
                        if Self.edgesX.contains(where: { abs($0 - cx) < margin }) { continue }
                        if Self.edgesY.contains(where: { abs($0 - cy) < margin }) { continue }
                        if cx > 0, cx < w, cy > 0, cy < h { predicted = Self.marker(x: cx, y: cy) }
                    }
                }
                let wanted = expect(predicted)
                let got = pixels[j * size.w + i]
                var d: Float = 0
                for c in 0..<4 { d = max(d, abs(got[c] - wanted[c])) }
                result.compared += 1
                if wanted.w == 0 { result.transparent += 1 }
                if !(d <= 2.0 / 255) {
                    result.failures += 1
                    if result.first.isEmpty { result.first = "pixel (\(i), \(j)): \(got) vs \(wanted)" }
                }
            }
        }
        return result
    }

    private func placement(_ fit: LayerFit, _ size: (w: Int, h: Int)) -> LayerFitPlacement {
        LayerFitPlacement(contentWidth: Self.photoWidth, contentHeight: Self.photoHeight, outputWidth: size.w,
                          outputHeight: size.h, fit: fit)
    }

    // MARK: - CMP-006-T08, T10: every mode, portrait then landscape output

    func testEveryModeDrawsWhereTheGeometryPredictsInPortraitThenLandscape() throws {
        var summary: [String] = []
        for mode in LayerFitMode.allCases {
            let fit = LayerFit(mode: mode)
            let rig = try makeRig(fit: fit)
            var time: UInt64 = 1
            for (name, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
                let pixels = try render(rig, size, startTime: time)
                time += 1_000_000_000
                // pixelAccurate: every output pixel centre is a texel centre, so (almost) no pixel is skipped.
                let margin: Double = mode == .pixelAccurate ? 0.4 : 1.0
                let r = check(pixels, size, placement(fit, size), margin: margin)
                let label = "\(mode) \(name)"
                XCTAssertEqual(r.failures, 0, "\(label): \(r.failures) of \(r.compared) pixels wrong; first \(r.first)")
                XCTAssertGreaterThan(r.compared, size.w * size.h / 2, "\(label): most pixels compared")
                switch mode {
                case .fill, .stretch: XCTAssertEqual(r.transparent, 0, "\(label): covers the output")
                case .fit, .pixelAccurate: XCTAssertGreaterThan(r.transparent, 0, "\(label): transparent bars")
                }
                summary.append("\(label): \(r.compared) px compared, \(r.transparent) transparent, \(r.failures) wrong")
            }
            XCTAssertEqual(rig.photo.state, .ready(width: Self.photoWidth, height: Self.photoHeight), "never reloaded")
        }
        print("CMP-006 GPU read-back: " + summary.joined(separator: "; "))
    }

    /// The acceptance: a top-anchored fill keeps the photo's yellow top band at the output's top in
    /// both orientations.
    func testATopAnchoredFillKeepsItsCropInLandscape() throws {
        let fit = LayerFit(mode: .fill, anchor: LayerPoint(x: 0.5, y: 0))
        let rig = try makeRig(fit: fit)
        for (time, size) in [(UInt64(1), Self.portrait), (UInt64(2_000_000_000), Self.landscape)] {
            let pixels = try render(rig, size, startTime: time)
            XCTAssertEqual(check(pixels, size, placement(fit, size), margin: 1).failures, 0)
            let topRow = (4..<(size.w - 4)).map { pixels[1 * size.w + $0] }
            assertAll(topRow, equal: Pixel(1, 1, 0, 1), tolerance: 2.0 / 255, "\(size.w)×\(size.h): the top band at the top")
        }
    }

    // MARK: - CMP-006-T10: blend mode, transform, apply, a layer without fitting

    func testAFittedLayerWithANonNormalBlendModeMatchesTheReference() throws {
        let backdrop = Pixel(0.2, 0.3, 0.4, 1)
        let fit = LayerFit(mode: .fit)
        let rig = try makeRig(fit: fit, blend: .screen, backdrop: backdrop)
        let b = LayerBlend.Pixel(Double(backdrop.x), Double(backdrop.y), Double(backdrop.z), Double(backdrop.w))
        for (time, size) in [(UInt64(1), Self.portrait), (UInt64(2_000_000_000), Self.landscape)] {
            let pixels = try render(rig, size, startTime: time)
            let r = check(pixels, size, placement(fit, size), margin: 1, expect: { (s: Pixel) -> Pixel in
                let source = LayerBlend.Pixel(Double(s.x), Double(s.y), Double(s.z), Double(s.w))
                let o = LayerBlend.composite(.screen, backdrop: b, source: source)
                return Pixel(Float(o.x), Float(o.y), Float(o.z), Float(o.w))
            })
            XCTAssertEqual(r.failures, 0, "screen over the backdrop, \(size.w)×\(size.h): first \(r.first)")
            XCTAssertGreaterThan(rig.compositor.blendDraws, 0, "drawn through the blend-mode path")
        }
    }

    func testAFittedLayerWithATransformIsFittedFirstThenPlaced() throws {
        let transform = try LayerTransform(translation: LayerPoint(x: 0.1, y: 0.05), uniformScale: 0.75, rotation: 0.3)
        let fit = LayerFit(mode: .fill)
        let rig = try makeRig(fit: fit, transform: transform)
        for (time, size) in [(UInt64(1), Self.portrait), (UInt64(2_000_000_000), Self.landscape)] {
            let pixels = try render(rig, size, startTime: time)
            let inverse = try XCTUnwrap(transform.matrix(outputWidth: size.w, outputHeight: size.h).inverse)
            let r = check(pixels, size, placement(fit, size), margin: 1.5, place: { (q: LayerPoint) -> LayerPoint? in
                let p = inverse.apply(q)
                return p
            })
            XCTAssertEqual(r.failures, 0, "fill then transform, \(size.w)×\(size.h): first \(r.first)")
            XCTAssertGreaterThan(r.transparent, 0, "the scaled-down layer leaves transparent space")
            XCTAssertGreaterThan(rig.compositor.transformedDraws, 0)
        }
    }

    func testAFitChangeAtApplyShowsNextFrameWithoutReloadingAndOtherLayersIgnoreIt() throws {
        var rig = try makeRig(fit: nil, backdrop: Pixel(0, 0, 0, 0))
        let size = Self.landscape
        var pixels = try render(rig, size, startTime: 1)
        XCTAssertEqual(check(pixels, size, placement(.default, size), margin: 1).failures, 0, "no fit set: fill at the centre")
        let allocations = rig.compositor.pictureAllocations
        // Fit on the photo; a fit on the solid layer (it does not adopt LayerFitting) changes nothing.
        let fit = LayerFit(mode: .fit, anchor: LayerPoint(x: 0, y: 0.5))
        let solidID = rig.stack.ids[0]
        try rig.stack.setSettings(LayerCompositeSettings(fit: LayerFit(mode: .pixelAccurate)), of: solidID)
        try rig.stack.setSettings(LayerCompositeSettings(fit: fit), of: rig.photoID)
        var calls = 0
        try rig.compositor.apply(rig.stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            throw .notReady
        }
        XCTAssertEqual(calls, 0, "no layer is created again")
        XCTAssertEqual(rig.photo.fit, fit, "the compositor handed the fit to the photo")
        pixels = try render(rig, size, startTime: 2_000_000_000)
        let r = check(pixels, size, placement(fit, size), margin: 1)
        XCTAssertEqual(r.failures, 0, "left-anchored fit from the next frame: first \(r.first)")
        assertAll((10..<30).map { pixels[$0 * size.w + 1] }, equal: Pixel(1, 0, 0, 1), tolerance: 2.0 / 255,
                  "left-anchored: the photo's red left edge touches the output's left edge")
        assertAll((10..<30).map { pixels[$0 * size.w + size.w - 2] }, equal: Pixel(0, 0, 0, 0), tolerance: 0,
                  "left-anchored: the bar is on the right")
        XCTAssertEqual(rig.compositor.pictureAllocations - allocations, 0, "same size, no new picture (output is new, not counted)")
        XCTAssertEqual(rig.photo.state, .ready(width: Self.photoWidth, height: Self.photoHeight), "not reloaded")
        // Back to no fit: the photo's default again.
        try rig.stack.setSettings(LayerCompositeSettings(), of: rig.photoID)
        try rig.compositor.apply(rig.stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in throw .notReady }
        XCTAssertNil(rig.photo.fit)
    }

    // MARK: - CMP-006-T08: a sideways-recorded portrait video in fit

    func testARotatedPortraitVideoFitsWithTransparentBars() async throws {
        let gpu = try GPURig()
        let url = directory.appendingPathComponent("rotated.mov")
        try await VideoFixtures.write(to: url, .init(frames: 10, rotated: true, solid: (200, 200, 200)))
        let video = VideoLayerSource(device: gpu.device)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .video), settings: LayerCompositeSettings(fit: LayerFit(mode: .fit)))
        let compositor = try Compositor(device: gpu.device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in video }
        video.content = .file(url)
        XCTAssertTrue(video.waitUntilBuffered())
        // Upright 48 × 64. Landscape 128 × 72: scale 1.125, 54 px wide at x 37…91. Portrait 72 × 128:
        // scale 1.5, 96 px high at y 16…112.
        let base: UInt64 = 50_000_000_000
        let landscape = try gpu.output(width: 128, height: 72)
        try gpu.frame(compositor, into: landscape, time: base)
        var all = try gpu.read(landscape)
        for y in [10, 36, 60] {
            assertAll((0..<35).map { all[y * 128 + $0] }, equal: Pixel(0, 0, 0, 0), tolerance: 0, "landscape row \(y): left bar")
            assertAll((94..<128).map { all[y * 128 + $0] }, equal: Pixel(0, 0, 0, 0), tolerance: 0, "landscape row \(y): right bar")
            XCTAssertTrue((40..<88).allSatisfy { all[y * 128 + $0].w > 0.99 && all[y * 128 + $0].x > 0.4 }, "landscape row \(y): video")
        }
        let portrait = try gpu.output(width: 72, height: 128)
        XCTAssertTrue(video.waitUntilBuffered())
        try gpu.frame(compositor, into: portrait, time: base + 16_666_667)
        all = try gpu.read(portrait)
        assertAll((0..<(14 * 72)).map { all[$0] }, equal: Pixel(0, 0, 0, 0), tolerance: 0, "portrait: top bar")
        assertAll(((114 * 72)..<(128 * 72)).map { all[$0] }, equal: Pixel(0, 0, 0, 0), tolerance: 0, "portrait: bottom bar")
        XCTAssertTrue((20..<108).allSatisfy { all[$0 * 72 + 36].w > 0.99 }, "portrait: the video column is opaque")
    }

    // MARK: - CMP-006-T11: GPU time per mode (a measurement; never an assertion)

    func testBenchGPUTimePerMode() throws {
        guard ProcessInfo.processInfo.environment["CMP006_BENCH"] == "1" else {
            throw XCTSkip("Set CMP006_BENCH=1 to measure GPU time per mode (Release, Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let image = ImageFixtures.image(width: 1080, height: 1920) { x, y in
            RGBA(r: UInt8(x % 256), g: UInt8(y % 256), b: 128, a: 255)
        }
        let url = directory.appendingPathComponent("bench.png")
        try ImageFixtures.encode(image, .png).write(to: url)
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        var lines: [String] = []
        for mode in LayerFitMode.allCases {
            let photo = ImageLayerSource(device: gpu.device)
            photo.content = .file(url)
            photo.waitUntilLoaded()
            var stack = LayerStack()
            try stack.add(LayerDescriptor(kind: .photo), settings: LayerCompositeSettings(fit: LayerFit(mode: mode)))
            let compositor = try Compositor(device: gpu.device)
            try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in photo }
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
            lines.append("\(mode.rawValue): median \(String(format: "%.3f", median)) ms, p95 \(String(format: "%.3f", p95)) ms")
        }
        print("CMP-006 GPU time per frame, 1080×1920 photo into 1920×1080 (whole frame: photo pass, composite, flash guard, output): "
              + lines.joined(separator: "; "))
    }
}
#endif
