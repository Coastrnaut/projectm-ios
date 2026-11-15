// MED-012-T05: the countdown through the MED-009 text layer and the real compositor (MED-012-S3; contract C3). An
// injected monotonic time; 128 × 64 output; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(CoreText)
import AnalysisFeatures
import Compositor
import Foundation
import Metal
import TextLayer
import XCTest

final class CountdownLayerTests: XCTestCase {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private let settings = CountdownOverlaySettings(isShown: true, style: TextOverlaySpec(font: .menlo, size: 0.25))
    private var time: UInt64 = 1

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this environment; the CPU tests cover the rest.")
        }
        self.device = device
        self.queue = queue
    }

    private func frame(_ compositor: Compositor, _ output: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time, contentScale: 1,
                                 reduceFlashing: false, audio: .empty)
        commands.commit()
        commands.waitUntilCompleted()
        time += 16_666_667
    }

    /// S3: updates every quarter second for 4 s of a 3 s countdown and a while after zero: the layer gets one string
    /// per shown second (03, 02, 01, 00) and rasterizes once each; nothing after zero.
    func testRedrawsOncePerSecondWhileRunningAndNotAfterZero() throws {
        let layer = TextLayerSource(device: device, name: "countdown")
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .countdown))
        let compositor = try Compositor(device: device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in layer }
        let output = try XCTUnwrap(device.makeTexture(descriptor: try XCTUnwrap(LayerPictureDescriptor(width: 128, height: 64)).textureDescriptor()))
        try frame(compositor, output)   // the first frame learns the picture size

        var timer = CountdownTimer(durationSeconds: 3)
        timer.start(at: 0)
        var text = ChangedText()
        var pushed: [String] = []
        var finished = 0
        for quarter in 0...24 {   // 0 … 6 s
            let now = Double(quarter) * 0.25
            if timer.advance(at: now) { finished += 1 }
            if let string = text.report(CountdownFormat.string(timer, at: now)) {
                pushed.append(string)
                layer.spec = settings.spec(for: string)
                try frame(compositor, output)
                layer.waitUntilRendered()
            }
            try frame(compositor, output)
        }
        XCTAssertEqual(pushed, ["00:03", "00:02", "00:01", "00:00"])
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(layer.rasterizationCount, 4, "one rasterization per shown second")
        XCTAssertEqual(layer.renderCount, 4, "CMP-013 reuses the picture between changes")
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
    }
}
#endif
