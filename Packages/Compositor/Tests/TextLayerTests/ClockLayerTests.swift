// MED-011-T05: the clock through the MED-009 text layer and the real compositor (MED-011-S2, S3; contract C3).
// A fixed injected clock (UTC, en_US_POSIX); 128 × 64 output; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(CoreText)
import AnalysisFeatures
import Compositor
import Foundation
import Metal
import TextLayer
import XCTest

final class ClockLayerTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let posix = Locale(identifier: "en_US_POSIX")
    /// 2026-03-04 14:05:09 UTC.
    private let start = Date(timeIntervalSince1970: 1_772_633_109)
    private let settings = ClockOverlaySettings(isShown: true, style: TextOverlaySpec(font: .menlo, size: 0.25))

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment; the CPU tests cover the rest.")
        }
        self.device = device
        self.queue = queue
    }

    /// A compositor whose stack is one `.clock` text layer, and its output picture.
    private func makeClock() throws -> (TextLayerSource, Compositor, MTLTexture) {
        let layer = TextLayerSource(device: device, name: "clock")
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .clock))
        let compositor = try Compositor(device: device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in layer }
        let d = try XCTUnwrap(LayerPictureDescriptor(width: 128, height: 64)).textureDescriptor()
        return (layer, compositor, try XCTUnwrap(device.makeTexture(descriptor: d)))
    }

    private var time: UInt64 = 1

    private func frame(_ compositor: Compositor, _ output: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time, contentScale: 1,
                                 reduceFlashing: false, audio: .empty)
        commands.commit()
        commands.waitUntilCompleted()
        time += 16_666_667
    }

    /// Prepares, feeds the clock's spec for `date`, waits for the rasterization and shows it.
    private func show(_ date: Date, text: ClockText, layer: TextLayerSource, compositor: Compositor, output: MTLTexture) throws {
        if let string = text.update(at: date, timeZone: utc) { layer.spec = settings.spec(for: string) }
        try frame(compositor, output)
        layer.waitUntilRendered()
        try frame(compositor, output)
    }

    private func read(_ texture: MTLTexture) throws -> [UInt16] {
        let rowBytes = texture.width * 8
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let count = texture.width * texture.height * 4
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt16.self, capacity: count), count: count))
    }

    private func newText() -> ClockText {
        ClockText(formatter: settings.makeFormatter(locale: posix, timeZone: utc))
    }

    /// S2 (roadmap acceptance): a fixed clock renders the same pixels twice; one minute later they differ.
    func testFixedClockRendersIdenticalPixelsAndAMinuteLaterDifferent() throws {
        let (a, compositorA, outputA) = try makeClock()
        let textA = newText()
        try show(start, text: textA, layer: a, compositor: compositorA, output: outputA)
        XCTAssertEqual(textA.current, "14:05")
        XCTAssertEqual(compositorA.outcome(ofLayer: 0), .rendered)
        let first = try read(outputA)
        XCTAssertTrue(first.contains { (h: UInt16) -> Bool in h != 0 }, "the clock drew something")

        let (b, compositorB, outputB) = try makeClock()
        try show(start, text: newText(), layer: b, compositor: compositorB, output: outputB)
        XCTAssertEqual(try read(outputB), first, "a second render of the same clock is pixel-identical")
        XCTAssertEqual(a.lastRendering?.checksum, b.lastRendering?.checksum)

        try show(start.addingTimeInterval(60), text: textA, layer: a, compositor: compositorA, output: outputA)
        XCTAssertEqual(textA.current, "14:06")
        XCTAssertNotEqual(try read(outputA), first, "one minute later the pixels change")
        XCTAssertNotEqual(a.lastRendering?.checksum, b.lastRendering?.checksum)
    }

    /// S3: one-second ticks within a minute (no seconds shown) rasterize and render the clock once.
    func testTicksWithinAMinuteRasterizeAndRenderOnce() throws {
        let (layer, compositor, output) = try makeClock()
        let text = newText()
        let minute = Date(timeIntervalSince1970: 1_772_633_100)   // 14:05:00
        // Deterministic first frame: prepare the picture size with no text yet, then wait for the clock's
        // rasterization before any frame can show it. (Through `show`, the first rasterization started inside
        // the frame's `prepare`, so whether that same frame showed it depended on the background queue winning
        // the race against `render`: CI saw 120 frames shown instead of 119 on a slow runner.)
        try frame(compositor, output)
        XCTAssertEqual(layer.framesShown, 0, "no text before the clock's first string")
        layer.spec = settings.spec(for: try XCTUnwrap(text.update(at: minute, timeZone: utc)))
        layer.waitUntilRendered()
        try frame(compositor, output)
        for second in 1..<60 {
            try show(minute.addingTimeInterval(TimeInterval(second)), text: text, layer: layer, compositor: compositor, output: output)
        }
        XCTAssertEqual(layer.rasterizationCount, 1, "one rasterization for one string")
        XCTAssertEqual(layer.renderCount, 1, "CMP-013 reuses the picture on every other frame")
        XCTAssertEqual(layer.framesShown, 119, "every frame after the first (which prepares the picture size) shows it")
        try show(minute.addingTimeInterval(60), text: text, layer: layer, compositor: compositor, output: output)
        XCTAssertEqual(layer.rasterizationCount, 2, "the next minute draws once more")
        XCTAssertEqual(layer.renderCount, 2)
    }
}
#endif
