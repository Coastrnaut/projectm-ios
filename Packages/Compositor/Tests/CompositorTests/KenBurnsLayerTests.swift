// MED-007-T05, T13: the Ken Burns acceptance through the real Metal compositor ("Start/end frames match specified
// crop rectangles"; MED-007-S1, S4; contracts/ken-burns.md K2). A 96 × 64 photo of 4 × 4-pixel colour blocks is drawn
// into a 48 × 32 output with injected frame times (100 ms apart):
//
// * the first frame is compared with the image cropped on the CPU to the start rectangle (pixels 16…63 × 8…39, a
//   1:1 crop: every output pixel is one texel), every pixel within 1/255 in linear light;
// * the frame whose elapsed time reaches the duration is compared with the end rectangle (pixels 60…83 × 40…55,
//   shown at 2×), every pixel whose sample does not straddle a block edge within 1/255;
// * a middle frame differs from both; render caching renders every moving frame, then reuses the held end; Reduce
//   Motion holds the start and renders once. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import Foundation
import ImageLayer
import Metal
import XCTest

final class KenBurnsLayerTests: XCTestCase {
    private static let imageWidth = 96
    private static let imageHeight = 64
    private static let block = 4
    private static let out = (w: 48, h: 32)
    private static let frameStep: UInt64 = 100_000_000
    /// Pixels 16…63 × 8…39: the output's shape at 1:1.
    private static let start = KenBurnsRect(validatingX: 16.0 / 96, y: 8.0 / 64, width: 48.0 / 96, height: 32.0 / 64)!
    /// Pixels 60…83 × 40…55: the output's shape at 2×.
    private static let end = KenBurnsRect(validatingX: 60.0 / 96, y: 40.0 / 64, width: 24.0 / 96, height: 16.0 / 64)!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED007-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The block photo and its CPU reference

    private static func blockColor(_ bx: Int, _ by: Int) -> ImageFixtures.RGBA {
        ImageFixtures.RGBA(r: UInt8(bx * 10 + 5), g: UInt8(by * 15 + 5), b: UInt8((bx * 7 + by * 11) % 256), a: 255)
    }

    private static func sRGBToLinear(_ v: UInt8) -> Float {
        let c: Double = Double(v) / 255
        let l: Double = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        return Float(l)
    }

    /// The linear colour of image pixel (x, y).
    private static func reference(x: Int, y: Int) -> Pixel {
        let c = blockColor(x / block, y / block)
        return Pixel(sRGBToLinear(c.r), sRGBToLinear(c.g), sRGBToLinear(c.b), 1)
    }

    private func photoURL() throws -> URL {
        let image = ImageFixtures.image(width: Self.imageWidth, height: Self.imageHeight) { (x: Int, y: Int) -> ImageFixtures.RGBA in
            Self.blockColor(x / Self.block, y / Self.block)
        }
        let url = directory.appendingPathComponent("blocks.png")
        try ImageFixtures.encode(image, .png).write(to: url)
        return url
    }

    private struct Rig {
        let gpu: GPURig
        let photo: ImageLayerSource
        let compositor: Compositor
        let output: MTLTexture
    }

    private func makeRig(motion: KenBurnsMotion?, reduceMotion: Bool = false) throws -> Rig {
        let gpu = try GPURig()
        let photo = ImageLayerSource(device: gpu.device)
        photo.content = .file(try photoURL())
        photo.waitUntilLoaded()
        XCTAssertEqual(photo.state, .ready(width: Self.imageWidth, height: Self.imageHeight))
        photo.kenBurns = motion
        photo.reduceMotion = reduceMotion
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .photo))
        let compositor = try Compositor(device: gpu.device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in photo }
        let output = try gpu.output(width: Self.out.w, height: Self.out.h)
        return Rig(gpu: gpu, photo: photo, compositor: compositor, output: output)
    }

    /// Frame k at 1 + k · 100 ms.
    private func frame(_ rig: Rig, _ k: Int) throws -> [Pixel] {
        try rig.gpu.frame(rig.compositor, into: rig.output, time: 1 + UInt64(k) * Self.frameStep)
        XCTAssertEqual(rig.compositor.lastFlashGain, 1, "a slow pan is never flash-limited")
        return try rig.gpu.read(rig.output)
    }

    private struct Comparison { var compared = 0; var failures = 0; var first = "" }

    /// Compares every output pixel with the image cropped to `crop`; with `skipBlockEdges`, pixels whose bilinear
    /// sample would mix two blocks are left out.
    private func compare(_ pixels: [Pixel], crop: KenBurnsRect, skipBlockEdges: Bool) -> Comparison {
        var result = Comparison()
        let w: Double = Double(Self.imageWidth), h: Double = Double(Self.imageHeight)
        for j in 0..<Self.out.h {
            for i in 0..<Self.out.w {
                let px: Double = (crop.x + (Double(i) + 0.5) / Double(Self.out.w) * crop.width) * w
                let py: Double = (crop.y + (Double(j) + 0.5) / Double(Self.out.h) * crop.height) * h
                if skipBlockEdges && (Self.nearBlockEdge(px) || Self.nearBlockEdge(py)) { continue }
                let wanted = Self.reference(x: Int(px), y: Int(py))
                let got = pixels[j * Self.out.w + i]
                var d: Float = 0
                for c in 0..<4 { d = max(d, abs(got[c] - wanted[c])) }
                result.compared += 1
                if !(d <= 1.0 / 255) {
                    result.failures += 1
                    if result.first.isEmpty { result.first = "pixel (\(i), \(j)): \(got) vs \(wanted)" }
                }
            }
        }
        return result
    }

    /// The bilinear footprint (± half a texel) crosses a block edge.
    private static func nearBlockEdge(_ v: Double) -> Bool {
        let b: Double = Double(block)
        let r: Double = v.truncatingRemainder(dividingBy: b)
        return r < 0.5 + 1e-6 || r > b - 0.5 - 1e-6
    }

    // MARK: - MED-007-T05: the acceptance

    /// "Start/end frames match specified crop rectangles."
    func testStartAndEndFramesMatchTheSpecifiedCropRectangles() throws {
        let motion = KenBurnsMotion(start: Self.start, end: Self.end, durationMilliseconds: 2_000, easing: .easeInOut)
        let rig = try makeRig(motion: motion)
        let first = try frame(rig, 0)
        let s = compare(first, crop: Self.start, skipBlockEdges: false)
        XCTAssertEqual(s.compared, Self.out.w * Self.out.h, "every pixel of the 1:1 start frame is compared")
        XCTAssertEqual(s.failures, 0, "start frame: \(s.failures) of \(s.compared) wrong; first \(s.first)")
        XCTAssertEqual(rig.photo.playhead.elapsedNanoseconds, 0)

        var middle: [Pixel] = []
        var last: [Pixel] = []
        for k in 1...20 {
            let pixels = try frame(rig, k)
            if k == 10 { middle = pixels }
            last = pixels
        }
        XCTAssertEqual(rig.photo.playhead.elapsedNanoseconds, 2_000_000_000, "frame 20 is the end time")
        let e = compare(last, crop: Self.end, skipBlockEdges: true)
        XCTAssertGreaterThan(e.compared, Self.out.w * Self.out.h / 2, "most end-frame pixels are compared")
        XCTAssertEqual(e.failures, 0, "end frame: \(e.failures) of \(e.compared) wrong; first \(e.first)")
        XCTAssertGreaterThan(compare(middle, crop: Self.start, skipBlockEdges: false).failures, 0, "the middle frame has moved")
        XCTAssertGreaterThan(compare(middle, crop: Self.end, skipBlockEdges: true).failures, 0, "and has not arrived")
        print("MED-007 GPU read-back: start \(s.compared) px, end \(e.compared) px compared, 0 wrong")
    }

    /// MED-007-R6: every moving frame renders; the frame reaching the end renders, the next renders once more (its key
    /// was not cacheable), then the held end is reused.
    func testMovingFramesRenderAndTheHeldEndIsReused() throws {
        let motion = KenBurnsMotion(start: Self.start, end: Self.end, durationMilliseconds: 2_000, easing: .linear)
        let rig = try makeRig(motion: motion)
        for k in 0...20 { _ = try frame(rig, k) }
        XCTAssertEqual(rig.photo.renderCount, 21, "no moving frame is reused")
        XCTAssertFalse(rig.photo.isKenBurnsMoving)
        for k in 21...25 { _ = try frame(rig, k) }
        XCTAssertEqual(rig.photo.renderCount, 22, "holding: rendered once more, then reused")
        XCTAssertEqual(rig.photo.framesShown, 26)
        let held = try rig.gpu.read(rig.output)
        XCTAssertEqual(compare(held, crop: Self.end, skipBlockEdges: true).failures, 0, "the reused picture is the end")

        rig.photo.kenBurns = motion.with(durationMilliseconds: 3_000)   // a new movement restarts at the start
        let restarted = try frame(rig, 26)
        XCTAssertEqual(compare(restarted, crop: Self.start, skipBlockEdges: false).failures, 0, "restarted at the start")
        XCTAssertTrue(rig.photo.isKenBurnsMoving)
    }

    /// MED-007-T13 (R7, S4): Reduce Motion shows the start rectangle on every frame and renders once.
    func testReduceMotionHoldsTheStartRectangle() throws {
        let motion = KenBurnsMotion(start: Self.start, end: Self.end, durationMilliseconds: 2_000)
        let rig = try makeRig(motion: motion, reduceMotion: true)
        for k in 0..<8 {
            let pixels = try frame(rig, k * 5)
            XCTAssertEqual(compare(pixels, crop: Self.start, skipBlockEdges: false).failures, 0, "frame \(k) shows the start")
        }
        XCTAssertEqual(rig.photo.renderCount, 1, "a still: rendered once, then reused")
        rig.photo.reduceMotion = false
        _ = try frame(rig, 40)
        XCTAssertTrue(rig.photo.isKenBurnsMoving, "Reduce Motion off: the movement runs from the start")
    }

    /// A slideshow's dwell overrides the duration without restarting.
    func testTheDurationOverrideSetsTheEndTime() throws {
        let motion = KenBurnsMotion(start: Self.start, end: Self.end, durationMilliseconds: 10_000)
        let rig = try makeRig(motion: motion)
        rig.photo.kenBurnsDurationNanoseconds = 1_000_000_000
        _ = try frame(rig, 0)
        var last: [Pixel] = []
        for k in 1...10 { last = try frame(rig, k) }
        XCTAssertEqual(compare(last, crop: Self.end, skipBlockEdges: true).failures, 0, "the end after the 1 s override")
        XCTAssertFalse(rig.photo.isKenBurnsMoving)
    }
}
#endif
