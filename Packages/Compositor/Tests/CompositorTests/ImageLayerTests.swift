// MED-001-T10, T17: the photo layer through the real Metal compositor (MED-001-R9, R10, S1, S5).
// 64 × 64 outputs; stored copies are written to a temporary folder by the sanitizer; skipped without
// a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import ImageLayer
import Metal
import UniformTypeIdentifiers
import XCTest

final class ImageLayerTests: XCTestCase {
    private typealias RGBA = ImageFixtures.RGBA
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED001-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func linear(_ code: UInt8) -> Float {
        let c = Float(code) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// Writes `image` as a lossless PNG stored copy (a JPEG copy would blur the test colors) and
    /// returns its URL.
    private func store(_ image: CGImage, name: String = "photo.png") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ImageFixtures.encode(image, .png).write(to: url)
        return url
    }

    private func make(_ rig: GPURig, mode: ImageScaleMode = .fill) throws -> (ImageLayerSource, Compositor) {
        let layer = ImageLayerSource(device: rig.device, mode: mode)
        return (layer, try Compositor(device: rig.device, layers: [layer]))
    }

    func testSolidPhotoReadsBackAsItsLinearValue() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig)
        XCTAssertEqual(layer.fallback, .transparent)
        layer.content = .file(try store(ImageFixtures.solid(RGBA(r: 188, g: 188, b: 188, a: 255))))
        layer.waitUntilLoaded()
        XCTAssertEqual(layer.state, .ready(width: 64, height: 48))
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        let v = linear(188)
        assertAll(try rig.read(output), equal: Pixel(v, v, v, 1), tolerance: 2.0 / 255, "sRGB 188 reads back linear")
        try rig.frame(compositor, into: output, time: 16_666_667)
        XCTAssertEqual(layer.framesShown, 2)
    }

    func testWidePhotoFillsASquareWithItsMiddleStripe() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig)
        let stripes = ImageFixtures.image(width: 30, height: 10) { x, _ in
            x < 10 ? RGBA(r: 255, g: 0, b: 0, a: 255) : x < 20 ? RGBA(r: 0, g: 255, b: 0, a: 255) : RGBA(r: 0, g: 0, b: 255, a: 255)
        }
        layer.content = .file(try store(stripes))
        layer.waitUntilLoaded()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let all = try rig.read(output)
        for y in [0, 31, 63] {
            assertAll((4..<60).map { all[y * 64 + $0] }, equal: Pixel(0, 1, 0, 1), tolerance: 2.0 / 255, "row \(y): only the middle stripe")
        }
    }

    func testFitLeavesTransparentBars() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig, mode: .fit)
        layer.content = .file(try store(ImageFixtures.solid(RGBA(r: 255, g: 255, b: 255, a: 255), width: 32, height: 8)))
        layer.waitUntilLoaded()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let all = try rig.read(output)
        assertAll(Array(all[0..<(20 * 64)]), equal: Pixel(0, 0, 0, 0), "top bar transparent")
        assertAll(Array(all[(30 * 64)..<(34 * 64)]), equal: Pixel(1, 1, 1, 1), tolerance: 2.0 / 255, "the image in the middle")
        assertAll(Array(all[(44 * 64)...]), equal: Pixel(0, 0, 0, 0), "bottom bar transparent")
    }

    func testHalfTransparentPhotoIsPremultiplied() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig)
        layer.content = .file(try store(ImageFixtures.solid(RGBA(r: 188, g: 188, b: 188, a: 128), width: 16, height: 16)))
        layer.waitUntilLoaded()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let a: Float = 128.0 / 255, v = linear(188) * a
        assertAll(try rig.read(output), equal: Pixel(v, v, v, a), tolerance: 3.0 / 255, "linear color × alpha")
    }

    func testNoContentLoadingAndFailureShowTheTransparentFallback() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig)
        let output = try rig.output()
        XCTAssertEqual(layer.state, .empty)
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady))
        assertAll(try rig.read(output), equal: Pixel(0, 0, 0, 0), "nothing without a photo")

        let jpeg = ImageFixtures.jpegWithMetadata(width: 64, height: 64)
        let corrupt = directory.appendingPathComponent("corrupt.jpg")
        try jpeg.prefix(jpeg.count / 2).write(to: corrupt)
        layer.content = .file(corrupt)
        layer.waitUntilLoaded()
        XCTAssertEqual(layer.state, .failed(.damaged), "a damaged stored copy fails with its typed error")
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "and the compositor keeps running")

        layer.content = .file(directory.appendingPathComponent("missing.jpg"))
        layer.waitUntilLoaded()
        XCTAssertEqual(layer.state, .failed(.unreadable))
        XCTAssertEqual(layer.framesShown, 0)
    }

    func testRemovingTheContentClearsTheNextFrameAndResizeDoesNotReload() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig)
        layer.content = .file(try store(ImageFixtures.solid(RGBA(r: 255, g: 0, b: 0, a: 255))))
        layer.waitUntilLoaded()
        try rig.frame(compositor, into: try rig.output(), time: 1)
        let large = try rig.output(width: 96, height: 48)
        try rig.frame(compositor, into: large, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "a new size shows the same image at once")
        assertAll(try rig.read(large), equal: Pixel(1, 0, 0, 1), tolerance: 2.0 / 255, "red at the new size")
        layer.content = .none
        XCTAssertEqual(layer.state, .empty)
        try rig.frame(compositor, into: large, time: 3)
        assertAll(try rig.read(large), equal: Pixel(0, 0, 0, 0), "removed: the next frame shows nothing")
    }

    func testAStaleLoadIsDropped() throws {
        let rig = try GPURig()
        let (layer, compositor) = try make(rig)
        let red = try store(ImageFixtures.solid(RGBA(r: 255, g: 0, b: 0, a: 255), width: 40, height: 40), name: "red.png")
        let blueURL = try store(ImageFixtures.solid(RGBA(r: 0, g: 0, b: 255, a: 255), width: 20, height: 20), name: "blue.png")
        layer.content = .file(red)
        layer.content = .file(blueURL)
        layer.waitUntilLoaded()
        XCTAssertEqual(layer.state, .ready(width: 20, height: 20), "the newest content wins")
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: Pixel(0, 0, 1, 1), tolerance: 2.0 / 255, "blue, never the stale red")
    }
}
#endif
