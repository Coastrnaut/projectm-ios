// MED-010-T07: the logo layer through the real sanitizer and Metal compositor — the compositing half of the
// acceptance (MED-010-R4, R7, R8, S2). The fixture is built in memory: 64 × 64, a magenta-ish colour with
// a horizontal alpha gradient 0…255 in the top 46 rows and a fully transparent block in the bottom 18
// (whose stored colour is black: the classic source of dark fringes). Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import ImageLayer
import Metal
import UniformTypeIdentifiers
import XCTest

/// The MED-010 fixture logo (shared with the import tests).
enum LogoFixture {
    static let size = 64
    static let opaqueRows = 46   // not a multiple of 4: the edge falls inside a mip-2 texel
    static let color = ImageFixtures.RGBA(r: 220, g: 40, b: 200, a: 255)

    /// Alpha at (x, y): x · 255 / 63 in the top 46 rows (0 at the left edge, 255 at the right), 0 below.
    static func alpha(x: Int, y: Int) -> UInt8 {
        guard y < opaqueRows else { return 0 }
        let a: Int = (x * 255 + 31) / 63
        return UInt8(a)
    }

    static func image() -> CGImage {
        ImageFixtures.image(width: size, height: size) { (x: Int, y: Int) -> ImageFixtures.RGBA in
            let a: UInt8 = alpha(x: x, y: y)
            return a == 0 ? ImageFixtures.RGBA(r: 0, g: 0, b: 0, a: 0) : ImageFixtures.RGBA(r: color.r, g: color.g, b: color.b, a: a)
        }
    }

    static func png() -> Data { ImageFixtures.encode(image(), .png) }
}

final class LogoLayerTests: XCTestCase {
    private var directory: URL!
    private let backdrop = Pixel(0.8, 0.7, 0.1, 1)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED010-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The fixture through the logo import path (sanitizer, PNG forced, logo limits) into a stored file.
    private func storedLogo() throws -> URL {
        let copy = try ImageSanitizer.sanitize(LogoFixture.png(), limits: LogoImport.limits, format: .png)
        XCTAssertEqual(copy.fileExtension, "png")
        let url = directory.appendingPathComponent("logo.png")
        try copy.data.write(to: url)
        return url
    }

    private func make(_ rig: GPURig, placement: LogoPlacement) throws -> (LogoLayerSource, Compositor) {
        let background = SolidLayer("backdrop", color: backdrop)
        let logo = LogoLayerSource(device: rig.device)
        logo.placement = placement
        logo.content = .file(try storedLogo())
        logo.waitUntilLoaded()
        return (logo, try Compositor(device: rig.device, layers: [background, logo]))
    }

    private func linear(_ code: UInt8) -> Float { PremultipliedLinear.linear(code) }

    /// Premultiplied "over" of the fixture's pixel (x, y) at `opacity` onto the backdrop, in linear light.
    private func expected(x: Int, y: Int, opacity: Float = 1) -> Pixel {
        let a: Float = Float(LogoFixture.alpha(x: x, y: y)) / 255 * opacity
        let c = LogoFixture.color
        let keep: Float = 1 - a
        let r: Float = linear(c.r) * a + backdrop.x * keep
        let g: Float = linear(c.g) * a + backdrop.y * keep
        let b: Float = linear(c.b) * a + backdrop.z * keep
        return Pixel(r, g, b, a + backdrop.w * keep)
    }

    /// The largest per-channel difference.
    private func diff(_ p: Pixel, _ q: Pixel) -> Float {
        let dx: Float = Swift.abs(p.x - q.x)
        let dy: Float = Swift.abs(p.y - q.y)
        let dz: Float = Swift.abs(p.z - q.z)
        let dw: Float = Swift.abs(p.w - q.w)
        return Swift.max(Swift.max(dx, dy), Swift.max(dz, dw))
    }

    /// S2: 1:1 placement (128 × 128 output, size 0.5, no margin, top left → the logo covers 0..<64 exactly).
    func testTheFixtureComposesAsPremultipliedOverInLinearLight() throws {
        let rig = try GPURig()
        let (logo, compositor) = try make(rig, placement: LogoPlacement(corner: .topLeft, size: 0.5, margin: 0))
        XCTAssertEqual(logo.state, .ready(width: 64, height: 64))
        let output = try rig.output(width: 128, height: 128)
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)
        let all = try rig.read(output)
        var worst: Float = 0
        var transparentWorst: Float = 0
        for y in 0..<64 {
            for x in 0..<64 {
                let got: Pixel = all[y * 128 + x]
                let want: Pixel = expected(x: x, y: y)
                let d: Float = diff(got, want)
                worst = max(worst, d)
                if y >= LogoFixture.opaqueRows { transparentWorst = max(transparentWorst, diff(got, backdrop)) }
            }
        }
        XCTAssertLessThanOrEqual(worst, 2.0 / 255, "S2: premultiplied over within 2/255")
        XCTAssertLessThanOrEqual(transparentWorst, 1.0 / 255, "S2: the transparent region shows the backdrop unchanged")
        // Outside the logo the backdrop is untouched.
        for (x, y) in [(100, 10), (10, 100), (127, 127)] {
            XCTAssertLessThanOrEqual(diff(all[y * 128 + x], backdrop), 1.0 / 255, "outside (\(x), \(y))")
        }
    }

    /// S2 (no dark fringe): drawn at a quarter of its size (mip level 2), no pixel of the logo's area is
    /// darker in any channel than both the backdrop and the logo's colour.
    func testAQuarterSizeLogoHasNoDarkFringe() throws {
        let rig = try GPURig()
        let (_, compositor) = try make(rig, placement: LogoPlacement(corner: .topLeft, size: 0.125, margin: 0))
        let output = try rig.output(width: 128, height: 128)
        try rig.frame(compositor, into: output, time: 1)
        let all = try rig.read(output)
        let c = LogoFixture.color
        let tolerance: Float = 2.0 / 255
        let floorR: Float = Swift.min(linear(c.r), backdrop.x) - tolerance
        let floorG: Float = Swift.min(linear(c.g), backdrop.y) - tolerance
        let floorB: Float = Swift.min(linear(c.b), backdrop.z) - tolerance
        var darkest: Float = 1
        for y in 0..<16 {
            for x in 0..<16 {
                let got: Pixel = all[y * 128 + x]
                let lowest: Float = Swift.min(got.x - floorR, Swift.min(got.y - floorG, got.z - floorB))
                darkest = Swift.min(darkest, lowest)
            }
        }
        XCTAssertGreaterThanOrEqual(darkest, 0, "S2: no channel darker than both the logo and the backdrop")
        // And the straight-alpha mistake would fail this: the bottom-left logo texels average to transparent.
        XCTAssertLessThanOrEqual(diff(all[15 * 128 + 0], backdrop), 2.0 / 255, "transparent corner shows the backdrop")
    }

    /// MED-010-R7, R8: opacity scales the premultiplied colour; one render per change, reuse otherwise.
    func testOpacityScalesAndTheLayerIsCachedUntilItChanges() throws {
        let rig = try GPURig()
        let (logo, compositor) = try make(rig, placement: LogoPlacement(corner: .topLeft, size: 0.5, margin: 0))
        let output = try rig.output(width: 128, height: 128)
        try rig.frame(compositor, into: output, time: 1)
        try rig.frame(compositor, into: output, time: 16_666_667)
        XCTAssertEqual(logo.renderCount, 1, "CMP-013: drawn once")
        XCTAssertEqual(logo.framesShown, 2)
        logo.placement = logo.placement.with(opacity: 0.6)
        try rig.frame(compositor, into: output, time: 33_333_334)
        XCTAssertEqual(logo.renderCount, 2, "the opacity change renders once")
        let all = try rig.read(output)
        for (x, y) in [(63, 10), (32, 20), (5, 40)] {
            XCTAssertLessThanOrEqual(diff(all[y * 128 + x], expected(x: x, y: y, opacity: 0.6)), 2.0 / 255, "opacity at (\(x), \(y))")
        }
        logo.placement = logo.placement.with(opacity: 0)
        try rig.frame(compositor, into: output, time: 50_000_001)
        XCTAssertLessThanOrEqual(diff(try rig.read(output)[10 * 128 + 63], backdrop), 1.0 / 255, "opacity 0 draws nothing")
    }

    func testNoContentAndAFailedLoadShowTheTransparentFallback() throws {
        let rig = try GPURig()
        let logo = LogoLayerSource(device: rig.device)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("backdrop", color: backdrop), logo])
        let output = try rig.output(width: 32, height: 32)
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertNotEqual(compositor.outcome(ofLayer: 1), .rendered)
        let missing = directory.appendingPathComponent("missing.png")
        logo.content = .file(missing)
        logo.waitUntilLoaded()
        XCTAssertEqual(logo.state, .failed(.unreadable))
        try rig.frame(compositor, into: output, time: 16_666_667)
        XCTAssertLessThanOrEqual(diff(try rig.read(output)[0], backdrop), 1.0 / 255)
    }

    /// MED-010-R3 at the sanitizer: an opaque picture stays lossless PNG when PNG is asked for.
    func testThePNGFormatKeepsAnOpaquePictureLossless() throws {
        let opaque = ImageFixtures.image(width: 8, height: 8) { (x: Int, y: Int) -> ImageFixtures.RGBA in
            ImageFixtures.RGBA(r: UInt8(x * 30), g: UInt8(y * 30), b: 7, a: 255)
        }
        let source = ImageFixtures.encode(opaque, .png)
        XCTAssertEqual(try ImageSanitizer.sanitize(source, limits: LogoImport.limits).fileExtension, "jpg", "automatic stays MED-001")
        let copy = try ImageSanitizer.sanitize(source, limits: LogoImport.limits, format: .png)
        XCTAssertEqual(copy.fileExtension, "png")
        let decoded = try ImageIODecoder().decode(copy.data, limits: LogoImport.limits)
        XCTAssertEqual(decoded.pixels, try ImageIODecoder().decode(source, limits: LogoImport.limits).pixels, "lossless")
    }
}
#endif
