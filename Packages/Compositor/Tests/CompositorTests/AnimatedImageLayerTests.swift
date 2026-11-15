// MED-008-T06 to T09: animated images through the import and the real Metal compositor ("Animated fixture loops and
// large file respects memory budget"; MED-008-S1 to S4; contracts/animated-image.md A1 to A3).
//
// * A 4-frame GIF generated with CGImageDestination (delays 10 ms, 200 ms, 50 ms, 300 ms; loop count 3) is imported:
//   the copy is an APNG with the same frames and delays, loop count 0, no metadata. Played through the compositor
//   with injected frame times 50 ms apart, every frame shows the colour `AnimationTimeline` picks (10 ms plays as
//   100 ms), and the frame at t + 650 ms equals the frame at t.
// * A 200-frame 2048 × 2048 APNG (hand-written) plays every frame with a 16 MB budget: the cache's peak accounted bytes
//   stay within it and frames are decoded far below 2048 px.
// * Reduce Motion holds frame 0 and renders once; Reduce flashing makes each frame last 334 ms.
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import Foundation
import ImageIO
import ImageLayer
import Metal
import XCTest

final class AnimatedImageLayerTests: XCTestCase {
    private static let colors: [ImageFixtures.RGBA] = [
        ImageFixtures.RGBA(r: 90, g: 40, b: 40, a: 255), ImageFixtures.RGBA(r: 40, g: 70, b: 40, a: 255),
        ImageFixtures.RGBA(r: 40, g: 40, b: 110, a: 255), ImageFixtures.RGBA(r: 70, g: 60, b: 40, a: 255),
    ]
    private static let delays: [Double] = [0.01, 0.2, 0.05, 0.3]
    private static let step: UInt64 = 50_000_000
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED008-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func linear(_ v: UInt8) -> Float {
        let c: Double = Double(v) / 255
        return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
    }

    /// The fixture colour nearest to `pixel`, and its distance.
    private static func classify(_ pixel: Pixel) -> (index: Int, distance: Float) {
        var best = (index: -1, distance: Float.infinity)
        for (i, c) in colors.enumerated() {
            let ref = Pixel(linear(c.r), linear(c.g), linear(c.b), 1)
            var d: Float = 0
            for k in 0..<4 { d = max(d, abs(pixel[k] - ref[k])) }
            if d < best.distance { best = (i, d) }
        }
        return best
    }

    /// The sanitized (imported) copy of the GIF fixture, written to a file.
    private func importedFixture() throws -> URL {
        let gif = AnimatedImageFixtures.gif(colors: Self.colors, delays: Self.delays, loopCount: 3)
        let copy = try ImageSanitizer.sanitize(gif, limits: .standard)
        let url = directory.appendingPathComponent("animation.\(copy.fileExtension)")
        try copy.data.write(to: url)
        return url
    }

    private struct Rig {
        let gpu: GPURig
        let photo: ImageLayerSource
        let compositor: Compositor
        let output: MTLTexture
    }

    private func makeRig(_ url: URL, budget: Int = 64 << 20, reduceMotion: Bool = false) throws -> Rig {
        let gpu = try GPURig()
        let photo = ImageLayerSource(device: gpu.device, animationBudgetBytes: budget)
        photo.content = .file(url)
        photo.waitUntilLoaded()
        photo.reduceMotion = reduceMotion
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .photo))
        let compositor = try Compositor(device: gpu.device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in photo }
        return Rig(gpu: gpu, photo: photo, compositor: compositor, output: try gpu.output(width: 16, height: 16))
    }

    /// Draws the frame at `time`; when the wanted frame was not decoded yet, waits for the decode and draws again at the
    /// same time (a zero frame duration). Returns the frame index shown.
    @discardableResult
    private func show(_ rig: Rig, time: UInt64, expecting: Int, reduceFlashing: Bool = false) throws -> Int {
        try rig.gpu.frame(rig.compositor, into: rig.output, time: time, reduceFlashing: reduceFlashing)
        if rig.photo.shownFrameIndex != expecting {
            rig.photo.waitUntilLoaded()
            try rig.gpu.frame(rig.compositor, into: rig.output, time: time, reduceFlashing: reduceFlashing)
        }
        rig.photo.waitUntilLoaded()   // the prefetch of the next frame
        return rig.photo.shownFrameIndex
    }

    private func centreColor(_ rig: Rig) throws -> Int {
        let pixels = try rig.gpu.read(rig.output)
        let hit = Self.classify(pixels[8 * 16 + 8])
        XCTAssertLessThan(hit.distance, 0.02, "the centre pixel is one of the fixture's colours")
        return hit.index
    }

    // MARK: - Import (MED-008-S4)

    func testImportStoresAnAnimatedPNGWithTheFramesAndDelaysAndNoMetadata() throws {
        let gif = AnimatedImageFixtures.gif(colors: Self.colors, delays: Self.delays, loopCount: 3)
        let copy = try ImageSanitizer.sanitize(gif, limits: .standard)
        XCTAssertEqual(copy.fileExtension, "png")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(copy.data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let facts = try XCTUnwrap(AnimatedImageProbe.facts(source))
        XCTAssertEqual(facts.frameCount, 4)
        XCTAssertEqual(facts.width, 32)
        for (stated, written) in zip(Self.delays, facts.rawDelays) { XCTAssertEqual(written ?? -1, stated, accuracy: 0.0011) }
        let container = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let png = container?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        XCTAssertEqual((png?[kCGImagePropertyAPNGLoopCount] as? NSNumber)?.intValue, 0, "always loops")
        let frame = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyGIFDictionary] {
            XCTAssertNil(frame[key], "no \(key) in the copy")
        }
        // Only what ImageIO's PNG writer derives from the pixels themselves (as for every still copy).
        let tags: [CGImageMetadataTag] = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { (m: CGImageMetadata) in
            CGImageMetadataCopyTags(m) as? [CGImageMetadataTag]
        } ?? []
        let names: Set<String> = Set(tags.compactMap { (t: CGImageMetadataTag) -> String? in CGImageMetadataTagCopyName(t) as String? })
        XCTAssertTrue(names.isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]), "no other metadata: \(names)")
        // A logo (always a still PNG) keeps the first frame; a still stays a still.
        let logo = try ImageSanitizer.sanitize(gif, limits: .standard, format: .png)
        XCTAssertNil(AnimatedImageProbe.facts(logo.data))
        let still = ImageFixtures.encode(ImageFixtures.solid(Self.colors[0]), .gif)
        XCTAssertNil(AnimatedImageProbe.facts(still))
    }

    // MARK: - The acceptance (MED-008-S1)

    /// "Animated fixture loops": every frame follows the clamped timeline, and the frame at t + total equals t.
    func testTheAnimatedFixtureLoopsThroughTheCompositorWithClampedDelays() throws {
        let rig = try makeRig(try importedFixture())
        XCTAssertEqual(rig.photo.state, .ready(width: 32, height: 32))
        XCTAssertEqual(rig.photo.animationFrameCount, 4)
        let timeline = AnimationTimeline(rawDelays: Self.delays.map { (d: Double) -> Double? in d }, reduceFlashing: false)
        XCTAssertEqual(timeline.delays, [100_000_000, 200_000_000, 50_000_000, 300_000_000], "10 ms plays as 100 ms")
        let loopSteps = Int(timeline.totalNanoseconds / Self.step)   // 13
        var shown: [Int] = []
        for k in 0..<(3 * loopSteps) {
            let expected: Int = timeline.frameIndex(elapsedNanoseconds: UInt64(k) * Self.step)
            let index = try show(rig, time: 1 + UInt64(k) * Self.step, expecting: expected)
            XCTAssertEqual(index, expected, "step \(k)")
            XCTAssertEqual(try centreColor(rig), expected, "step \(k): the drawn colour is frame \(expected)'s")
            XCTAssertEqual(rig.compositor.lastFlashGain, 1, "dim frames are never flash-limited")
            shown.append(index)
        }
        for k in 0..<(2 * loopSteps) { XCTAssertEqual(shown[k + loopSteps], shown[k], "frame(t + total) == frame(t), step \(k)") }
        XCTAssertEqual(Array(shown.prefix(loopSteps)), [0, 0, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 3])
        XCTAssertTrue(rig.photo.renderDependencies.time, "an animation is never cached")
    }

    // MARK: - The acceptance (MED-008-S2)

    /// "Large file respects memory budget": 200 frames of 2048 × 2048 play through within a 16 MB budget.
    func testALargeAnimationPlaysEveryFrameWithinTheMemoryBudget() throws {
        let frames = 200
        let url = directory.appendingPathComponent("large.png")
        try AnimatedImageFixtures.apng(width: 2048, height: 2048, frames: frames).write(to: url)
        let budget: Int = 16 << 20
        let rig = try makeRig(url, budget: budget)
        XCTAssertEqual(rig.photo.animationFrameCount, frames)
        for k in 0..<frames {
            XCTAssertEqual(try show(rig, time: 1 + UInt64(k) * 100_000_000, expecting: k), k, "frame \(k) is shown")
        }
        let stats = try XCTUnwrap(rig.photo.animationCacheStatistics)
        XCTAssertEqual(stats.budgetBytes, budget)
        XCTAssertLessThanOrEqual(stats.peakBytes, budget, "the cache never accounts more than its budget")
        XCTAssertLessThanOrEqual(stats.residentBytes, budget)
        XCTAssertLessThan(stats.frameWidth, 2048, "frames are decoded below full size")
        XCTAssertGreaterThanOrEqual(stats.decodes, frames)
        XCTAssertLessThan(stats.residentFrames, 10, "a small ring, not every frame")
        let fullSize: Int = frames * 2048 * 2048 * 4
        XCTAssertLessThan(stats.peakBytes * 100, fullSize, "under 1 % of decoding every frame at full size")
    }

    // MARK: - Sensory safety (MED-008-S3)

    func testReduceMotionShowsTheFirstFrameAndRendersOnce() throws {
        let rig = try makeRig(try importedFixture(), reduceMotion: true)
        for k in 0..<10 {
            try rig.gpu.frame(rig.compositor, into: rig.output, time: 1 + UInt64(k) * Self.step)
            XCTAssertEqual(try centreColor(rig), 0, "frame \(k) shows the first frame")
        }
        XCTAssertFalse(rig.photo.isAnimating)
        XCTAssertFalse(rig.photo.renderDependencies.time)
        XCTAssertEqual(rig.photo.renderCount, 1, "a held first frame is cached")
        XCTAssertEqual(rig.photo.framesShown, 10)
    }

    func testReduceFlashingPlaysEveryFrameForAtLeast334Milliseconds() throws {
        let rig = try makeRig(try importedFixture())
        let reduced = AnimationTimeline(rawDelays: Self.delays.map { (d: Double) -> Double? in d }, reduceFlashing: true)
        XCTAssertEqual(reduced.delays, [334_000_000, 334_000_000, 334_000_000, 334_000_000])
        for k in 0..<20 {
            let expected: Int = reduced.frameIndex(elapsedNanoseconds: UInt64(k) * Self.step)
            XCTAssertEqual(try show(rig, time: 1 + UInt64(k) * Self.step, expecting: expected, reduceFlashing: true), expected,
                           "step \(k)")
        }
    }

    // MARK: - Everywhere a photo goes (MED-008-T09)

    func testAPreparedSlideKenBurnsAndAStillKeepWorking() throws {
        let url = try importedFixture()
        let gpu = try GPURig()
        let photo = ImageLayerSource(device: gpu.device)
        photo.preload(url)
        photo.waitUntilLoaded()
        XCTAssertTrue(photo.isPrepared(url))
        photo.content = .file(url)
        XCTAssertEqual(photo.animationFrameCount, 4, "the prepared slide is adopted with its animation at once")
        XCTAssertEqual(photo.state, .ready(width: 32, height: 32))
        photo.kenBurns = KenBurnsPreset.zoomIn.motion()
        _ = photo.renderDependencies
        XCTAssertTrue(photo.isAnimating)
        XCTAssertTrue(photo.isKenBurnsMoving)
        let still = directory.appendingPathComponent("still.png")
        try ImageFixtures.encode(ImageFixtures.solid(Self.colors[1]), .png).write(to: still)
        photo.content = .file(still)
        photo.waitUntilLoaded()
        XCTAssertEqual(photo.animationFrameCount, 0)
        XCTAssertNil(photo.animationCacheStatistics)
        XCTAssertFalse(photo.isAnimating)
    }
}
#endif
