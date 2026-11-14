// Photo layer dark-fringe fix: a partially transparent PNG drawn below 1:1 must not darken its soft
// edges. The fixture is built in memory: 64 × 64, a magenta-ish colour with a horizontal alpha gradient
// 0…255 in the top 46 rows and a fully transparent block in the bottom 18 (stored colour black, the
// classic source of dark fringes when straight-alpha texels are filtered). Port of MED-010's logo test
// (S2) to the MED-001 photo layer. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import ImageLayer
import Metal
import UniformTypeIdentifiers
import XCTest

final class PhotoLayerFringeTests: XCTestCase {
    private typealias RGBA = ImageFixtures.RGBA
    private static let size = 64
    private static let opaqueRows = 46   // not a multiple of 4: the edge falls inside a mip-2 texel
    private static let color = RGBA(r: 220, g: 40, b: 200, a: 255)
    private let backdrop = Pixel(0.8, 0.7, 0.1, 1)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoFringe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func linear(_ code: UInt8) -> Float {
        let c: Float = Float(code) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    private static func alpha(x: Int, y: Int) -> UInt8 {
        guard y < opaqueRows else { return 0 }
        return UInt8((x * 255 + 31) / 63)
    }

    private func storedFixture() throws -> URL {
        let image: CGImage = ImageFixtures.image(width: Self.size, height: Self.size) { (x: Int, y: Int) -> RGBA in
            let a: UInt8 = Self.alpha(x: x, y: y)
            let c: RGBA = Self.color
            return a == 0 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: c.r, g: c.g, b: c.b, a: a)
        }
        let url = directory.appendingPathComponent("fringe.png")
        try ImageFixtures.encode(image, .png).write(to: url)
        return url
    }

    /// Backdrop below, the photo (fit, so the square image covers the square output) on top.
    private func render(outputSize: Int) throws -> [Pixel] {
        let rig = try GPURig()
        let photo = ImageLayerSource(device: rig.device, mode: .fit)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("backdrop", color: backdrop), photo])
        photo.content = .file(try storedFixture())
        photo.waitUntilLoaded()
        XCTAssertEqual(photo.state, .ready(width: Self.size, height: Self.size))
        let output = try rig.output(width: outputSize, height: outputSize)
        try rig.frame(compositor, into: output, time: 1)
        return try rig.read(output)
    }

    /// The lowest margin of any channel above min(image colour, backdrop) (negative: a dark fringe).
    private func darkestMargin(_ pixels: [Pixel], width: Int, rows: Range<Int>) -> Float {
        let c: RGBA = Self.color
        let floorR: Float = Swift.min(linear(c.r), backdrop.x)
        let floorG: Float = Swift.min(linear(c.g), backdrop.y)
        let floorB: Float = Swift.min(linear(c.b), backdrop.z)
        var darkest: Float = 1
        for y in rows {
            for x in 0..<width {
                let got: Pixel = pixels[y * width + x]
                let lowest: Float = Swift.min(got.x - floorR, Swift.min(got.y - floorG, got.z - floorB))
                darkest = Swift.min(darkest, lowest)
            }
        }
        return darkest
    }

    /// At a quarter (mip level 2) and at 3/8 (between mip levels, fractional texel positions), no channel
    /// of any pixel is darker than both the image colour and the backdrop.
    func testReducedPhotoHasNoDarkFringe() throws {
        for outputSize in [16, 24] {
            let pixels: [Pixel] = try render(outputSize: outputSize)
            let darkest: Float = darkestMargin(pixels, width: outputSize, rows: 0..<outputSize)
            print("PhotoLayerFringe: output \(outputSize) px, darkest margin \(darkest)")
            XCTAssertGreaterThanOrEqual(darkest, -2.0 / 255, "\(outputSize) px: no channel darker than both the image and the backdrop")
        }
    }

    /// At 1:1 the fully transparent rows show the backdrop unchanged, and the soft edge is the
    /// premultiplied over of the image colour.
    func testTransparentAreaLeavesTheBackdropUnchanged() throws {
        let pixels: [Pixel] = try render(outputSize: Self.size)
        let c: RGBA = Self.color
        let colour = Pixel(linear(c.r), linear(c.g), linear(c.b), 1)
        var transparentWorst: Float = 0
        var edgeWorst: Float = 0
        for y in 0..<Self.size {
            for x in 0..<Self.size {
                let got: Pixel = pixels[y * Self.size + x]
                let a: Float = Float(Self.alpha(x: x, y: y)) / 255
                let expected: Pixel = colour * a + backdrop * (1 - a)
                let d: Float = Swift.max(Swift.abs(got.x - expected.x), Swift.max(Swift.abs(got.y - expected.y), Swift.abs(got.z - expected.z)))
                if y >= Self.opaqueRows + 1 { transparentWorst = Swift.max(transparentWorst, d) }
                if y < Self.opaqueRows - 1 { edgeWorst = Swift.max(edgeWorst, d) }
            }
        }
        XCTAssertLessThanOrEqual(transparentWorst, 1.0 / 255, "the transparent area shows the backdrop unchanged")
        XCTAssertLessThanOrEqual(edgeWorst, 3.0 / 255, "premultiplied over at 1:1")
    }
}
#endif
