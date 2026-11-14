// MED-006-T05: slides through the real photo layer and compositor (MED-006-R8, R9; S1 pixels, S6;
// contract C3). Five solid-colour PNGs cycled with `preload`: every change is a cut that renders the
// layer exactly once (CMP-013 key changes once), the frame after it shows the new colour in full (no
// transparent frame, no blend), and later frames reuse the picture. Small outputs; skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import Foundation
import ImageLayer
import Metal
import XCTest

final class SlideshowLayerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED006-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let colors: [(ImageFixtures.RGBA, Pixel)] = [
        (ImageFixtures.RGBA(r: 255, g: 0, b: 0, a: 255), Pixel(1, 0, 0, 1)),
        (ImageFixtures.RGBA(r: 0, g: 255, b: 0, a: 255), Pixel(0, 1, 0, 1)),
        (ImageFixtures.RGBA(r: 0, g: 0, b: 255, a: 255), Pixel(0, 0, 1, 1)),
        (ImageFixtures.RGBA(r: 255, g: 255, b: 0, a: 255), Pixel(1, 1, 0, 1)),
        (ImageFixtures.RGBA(r: 255, g: 0, b: 255, a: 255), Pixel(1, 0, 1, 1)),
    ]

    private func slides() throws -> [URL] {
        try Self.colors.enumerated().map { (entry: (offset: Int, element: (ImageFixtures.RGBA, Pixel))) throws -> URL in
            let url = directory.appendingPathComponent("slide\(entry.offset).png")
            try ImageFixtures.encode(ImageFixtures.solid(entry.element.0, width: 40, height: 20), .png).write(to: url)
            return url
        }
    }

    /// The acceptance's pixels: the saved order 2, 0, 4, 1, 3 shows each slide's colour, each change a
    /// one-render cut with no transparent or mixed frame.
    func testPreparedSlidesCutInOrderAndRenderOncePerChange() throws {
        let rig = try RenderCacheCompositeTests.Rig(gpu: try GPURig())
        let layer = ImageLayerSource(device: rig.gpu.device)
        let urls = try slides()
        let order: [Int] = [2, 0, 4, 1, 3]
        layer.content = .file(urls[order[0]])
        layer.waitUntilLoaded()
        try rig.add(layer)
        try rig.apply()
        try rig.frames(3)
        XCTAssertEqual(layer.renderCount, 1)
        assertAll(try rig.pixels(), equal: Self.colors[order[0]].1, tolerance: 2.0 / 255, "the first slide")
        var dependencies = layer.renderDependencies
        for step in 1..<(order.count * 2) {
            let next: Int = order[step % order.count]
            layer.preload(urls[next])
            layer.waitUntilLoaded()   // the decode ran ahead on the layer's queue
            XCTAssertTrue(layer.isPrepared(urls[next]))
            try rig.frames(2)
            XCTAssertEqual(layer.renderDependencies, dependencies, "step \(step): preloading changes nothing drawn")
            let before: Int = layer.renderCount
            layer.content = .file(urls[next])
            XCTAssertEqual(layer.state, .ready(width: 40, height: 20), "step \(step): adopted at once")
            XCTAssertNotEqual(layer.renderDependencies, dependencies, "step \(step): the cache key changes")
            dependencies = layer.renderDependencies
            try rig.frame()
            XCTAssertEqual(layer.renderCount, before + 1, "step \(step): exactly one render")
            assertAll(try rig.pixels(), equal: Self.colors[next].1, tolerance: 2.0 / 255,
                      "step \(step): the frame after the change shows the new slide in full (a cut)")
            try rig.frames(3)
            XCTAssertEqual(layer.renderCount, before + 1, "step \(step): then reused")
            XCTAssertEqual(layer.renderDependencies, dependencies, "step \(step): the key changed exactly once")
        }
        XCTAssertNil(layer.preparedURL, "the prepared slot was consumed")
    }

    /// Without a finished preload the MED-001 path applies; a preload in flight is reused by the load
    /// (one decode), and a failing preload leaves the layer unchanged.
    func testUnpreparedChangeLoadsAndAFailedPreloadChangesNothing() throws {
        let rig = try RenderCacheCompositeTests.Rig(gpu: try GPURig())
        let layer = ImageLayerSource(device: rig.gpu.device)
        let urls = try slides()
        layer.content = .file(urls[0])
        layer.waitUntilLoaded()
        try rig.add(layer)
        try rig.apply()
        try rig.frame()
        let missing = directory.appendingPathComponent("missing.png")
        layer.preload(missing)
        layer.waitUntilLoaded()
        XCTAssertFalse(layer.isPrepared(missing))
        try rig.frame()
        assertAll(try rig.pixels(), equal: Self.colors[0].1, tolerance: 2.0 / 255, "a failed preload changes nothing")
        layer.content = .file(urls[1])   // not prepared: loads on the queue
        layer.waitUntilLoaded()
        try rig.frame()
        assertAll(try rig.pixels(), equal: Self.colors[1].1, tolerance: 2.0 / 255, "loaded and shown")
    }
}
#endif
