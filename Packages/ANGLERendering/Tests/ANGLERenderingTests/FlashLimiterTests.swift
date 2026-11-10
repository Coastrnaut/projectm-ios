// Task T104: the Reduce-flashing post-pass (FR-072) on the iOS Simulator through ANGLE's Metal
// backend. Solid-color frames make the expected luminance exact: a black → white cut becomes a ramp
// of at most `maxStep` per frame, in both directions, and the output's mean follows the adapted
// value. The ≤ 2 ms per frame criterion is a device measurement; simulator results are never device
// evidence.
import XCTest
import CANGLE
import Rendering
@testable import ANGLERendering

@MainActor
final class FlashLimiterTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private var renderer: ANGLERenderer!
    private var limiter: OpaquePointer!
    private var size: (width: Int32, height: Int32) = (0, 0)

    override func setUp() async throws {
        renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        renderer.view.layoutIfNeeded()
        renderer.makeSurfaceCurrent()
        limiter = try XCTUnwrap(PMFlashLimiterCreate(), "shaders compile and link")
        size = (Int32(renderer.currentSurfaceSize.width), Int32(renderer.currentSurfaceSize.height))
    }

    override func tearDown() async throws {
        renderer.makeSurfaceCurrent()
        PMFlashLimiterDestroy(limiter)
        renderer = nil
    }

    /// One frame of a solid gray `value` through the limiter; returns the adapted luminance.
    @discardableResult
    private func frame(_ value: Float, maxStep: Float) -> Float {
        renderer.makeSurfaceCurrent()
        let framebuffer = PMFlashLimiterBegin(limiter, size.width, size.height)
        XCTAssertNotEqual(framebuffer, 0)
        PMANGLEClearFramebuffer(framebuffer, value, value, value)
        PMFlashLimiterFinish(limiter, 0, maxStep)
        return PMFlashLimiterAdaptedLuminance(limiter)
    }

    /// Mean luminance of the window surface (squared encoded value, as the limiter computes it).
    private func outputLuminance() -> Float {
        let pixels = renderer.readPixels()
        XCTAssertFalse(pixels.isEmpty)
        var sum: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i]) / 255, g = Float(pixels[i + 1]) / 255, b = Float(pixels[i + 2]) / 255
            sum += 0.2126 * r * r + 0.7152 * g * g + 0.0722 * b * b
        }
        return sum / Float(pixels.count / 4)
    }

    func testTheFirstFrameStartsFromItsOwnBrightness() {
        XCTAssertEqual(frame(1, maxStep: 0.01), 1, accuracy: 0.01, "no ramp from a stale value")
        XCTAssertEqual(outputLuminance(), 1, accuracy: 0.02)
    }

    func testACutToWhiteBecomesARamp() {
        frame(0, maxStep: 1)
        var previous: Float = 0
        for n in 1...10 {
            let adapted = frame(1, maxStep: 0.05)
            XCTAssertEqual(adapted, min(Float(n) * 0.05, 1), accuracy: 0.003, "frame \(n)")
            XCTAssertLessThanOrEqual(adapted - previous, 0.05 + 0.003)
            previous = adapted
        }
        XCTAssertEqual(outputLuminance(), previous, accuracy: 0.03, "the white frame is dimmed to the adapted value")
    }

    func testACutToBlackBecomesARamp() {
        frame(1, maxStep: 1)
        let adapted = frame(0, maxStep: 0.1)
        XCTAssertEqual(adapted, 0.9, accuracy: 0.003)
        XCTAssertEqual(outputLuminance(), 0.9, accuracy: 0.03, "the black frame is lifted to the adapted value")
        for _ in 0..<12 { frame(0, maxStep: 0.1) }
        XCTAssertEqual(frame(0, maxStep: 0.1), 0, accuracy: 0.003)
        XCTAssertEqual(outputLuminance(), 0, accuracy: 0.01)
    }

    func testAlternatingFlashesAreFlattened() {
        frame(0.25, maxStep: 1)
        var lows: [Float] = [], highs: [Float] = []
        for n in 0..<30 {
            let adapted = frame(n.isMultiple(of: 2) ? 1 : 0, maxStep: Self.stepAt60)
            if n.isMultiple(of: 2) { highs.append(adapted) } else { lows.append(adapted) }
        }
        let swing = zip(highs, lows).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThanOrEqual(swing, Self.stepAt60 + 0.003, "a 30 Hz black/white flash moves the mean by one step at most")
    }

    func testResetStartsOverFromTheNextFrame() {
        frame(0, maxStep: 1)
        PMFlashLimiterReset(limiter)
        XCTAssertEqual(frame(1, maxStep: 0.01), 1, accuracy: 0.01)
    }

    /// The renderer path: the engine renders into the limiter and the result reaches the surface.
    func testTheRendererUsesTheLimiterOnlyWhenOn() async throws {
        let preset = Preset(id: "tests/001-line.milk", name: "001-line",
                            fileURL: Self.testPresets.appendingPathComponent("001-line.milk"))
        try await renderer.setPreset(preset)
        renderer.renderFrame(present: false)
        XCTAssertNil(renderer.flashLimiterAdaptedLuminance, "off by default: the limiter is not created")
        XCTAssertTrue(renderer.supportsReduceFlashing)
        renderer.reduceFlashing = true
        for _ in 0..<5 { XCTAssertTrue(renderer.renderFrame(present: false)) }
        let adapted = try XCTUnwrap(renderer.flashLimiterAdaptedLuminance)
        XCTAssertGreaterThanOrEqual(adapted, 0)
        XCTAssertLessThanOrEqual(adapted, 1)
        XCTAssertFalse(renderer.readPixels().isEmpty)
    }

    private static let stepAt60 = ANGLERenderer.flashLimitPerSecond / 60
}
