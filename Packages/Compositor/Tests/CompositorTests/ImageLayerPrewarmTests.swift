// ImageLayerPrewarmTests.swift — PERF-005-T10 (R11): a texture decoded ahead by the prewarm scheduler is adopted
// when the layer's content becomes its URL: ready at once, no load of the layer's own, and it draws. A miss loads
// as before. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import ImageLayer
import Metal
import XCTest

final class ImageLayerPrewarmTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PERF005-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ImageFixtures.encode(ImageFixtures.solid(ImageFixtures.RGBA(r: 200, g: 40, b: 40, a: 255)), .png).write(to: url)
        return url
    }

    func testAPrewarmedTextureIsAdoptedWithoutALoad() throws {
        let rig = try GPURig()
        let url = try store("next.png")
        // The scheduler's two halves: decode (any thread), then the texture.
        guard case .success(let image) = ImageLayerSource.decodeStored(url) else { return XCTFail("decode") }
        let texture = try XCTUnwrap(ImageLayerSource.makeLayerTexture(image, device: rig.device))
        XCTAssertEqual(ImageLayerSource.textureBytes(width: 64, height: 48), 64 * 48 * 4 + 32 * 24 * 4 + 16 * 12 * 4
                       + 8 * 6 * 4 + 4 * 3 * 4 + 2 * 1 * 4 + 1 * 1 * 4)

        let layer = ImageLayerSource(device: rig.device)
        var asked: [URL] = []
        layer.prewarmedTexture = { (requested: URL) -> MTLTexture? in
            asked.append(requested)
            return requested == url ? texture : nil
        }
        let compositor = try Compositor(device: rig.device, layers: [layer])
        layer.content = .file(url)
        XCTAssertEqual(layer.state, .ready(width: 64, height: 48), "ready at once, before any load could finish")
        XCTAssertEqual(layer.loadsStarted, 0, "no second decode")
        XCTAssertEqual(layer.prewarmedAdoptions, 1)
        XCTAssertEqual(asked, [url])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "the adopted picture draws on the first frame")

        // A miss loads as before.
        let other = try store("other.png")
        layer.content = .file(other)
        layer.waitUntilLoaded()
        XCTAssertEqual(layer.loadsStarted, 1)
        XCTAssertEqual(layer.state, .ready(width: 64, height: 48))
    }
}
#endif
