// Task T071: GLESRenderer renders the engine's upstream test preset on the iOS Simulator. The view
// is laid out off screen at a fixed size, frames are rendered directly (no display link), and the
// framebuffer is read back. Also: the reader is drained at most maxSamplesPerFrame per frame,
// pause/resume, and a failed preset keeps the previous one (FR-045).
import XCTest
import AudioCore
import ProjectMBridge
@testable import Rendering

@MainActor
final class GLESRendererTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private func preset(_ file: String) -> Preset {
        Preset(id: "tests/\(file)", name: file, fileURL: Self.testPresets.appendingPathComponent(file))
    }

    private func makeLaidOut(width: CGFloat = 64, height: CGFloat = 64) throws -> GLESRenderer {
        let renderer = try GLESRenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        renderer.view.layoutIfNeeded()
        return renderer
    }

    /// Counts pixels that are not black.
    private func litPixels(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }.count
    }

    /// T119: the fallback runs the same Reduce-flashing post-pass as ANGLERenderer (CFlashLimiter
    /// through PMAppleGLESLoadProc). Off by default, the limiter is not created; on, frames go through it.
    func testTheFallbackLimitsFlashingWhenOn() async throws {
        let renderer = try makeLaidOut()
        XCTAssertTrue(renderer.supportsReduceFlashing)
        try await renderer.setPreset(preset("001-line.milk"))
        XCTAssertTrue(renderer.renderFrame())
        XCTAssertNil(renderer.flashLimiterAdaptedLuminance, "off by default")
        renderer.reduceFlashing = true
        for _ in 0..<5 { XCTAssertTrue(renderer.renderFrame()) }
        let adapted = try XCTUnwrap(renderer.flashLimiterAdaptedLuminance, "the limiter ran")
        XCTAssertGreaterThanOrEqual(adapted, 0)
        XCTAssertLessThanOrEqual(adapted, 1)
        XCTAssertFalse(renderer.readPixels().isEmpty)
    }

    func testDrawableFollowsTheViewSizeAtDisplayScale() throws {
        let renderer = try makeLaidOut(width: 80, height: 40)
        let scale = renderer.view.contentScaleFactor
        XCTAssertEqual(renderer.currentDrawableSize.width, Int((80 * scale).rounded()))
        XCTAssertEqual(renderer.currentDrawableSize.height, Int((40 * scale).rounded()))
        renderer.view.frame = CGRect(x: 0, y: 0, width: 40, height: 80)
        renderer.view.layoutIfNeeded()
        XCTAssertEqual(renderer.currentDrawableSize.width, Int((40 * scale).rounded()))
    }

    func testRendersTheUpstreamTestPreset() async throws {
        let renderer = try makeLaidOut()
        try await renderer.setPreset(preset("100-square.milk"))
        for _ in 0..<30 { XCTAssertTrue(renderer.renderFrame()) }
        let pixels = renderer.readPixels()
        XCTAssertFalse(pixels.isEmpty)
        XCTAssertGreaterThan(litPixels(pixels), 0, "the preset drew something")
    }

    func testDrainsTheReaderUpToMaxSamplesPerFrame() throws {
        let renderer = try makeLaidOut()
        let ring = NormalizedPCMRing()
        let frames = 2_000
        let samples = (0..<(frames * 2)).map { Float(sin(Double($0) / 10)) * 0.5 }
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: frames) }
        renderer.attach(pcm: ring)
        renderer.renderFrame()
        let max = Int(ProjectMEngine.maxSamplesPerFrame)
        // The freshness rule keeps 50 ms (2,205 frames), so a 2,000-frame backlog is all readable.
        XCTAssertEqual(ring.availableFrames, Swift.max(0, frames - max))
        renderer.renderFrame()   // an empty or short reader is fine
    }

    func testFailedPresetKeepsThePreviousOne() async throws {
        let renderer = try makeLaidOut()
        try await renderer.setPreset(preset("100-square.milk"))
        do {
            try await renderer.setPreset(preset("missing.milk"))
            XCTFail("a missing preset should fail")
        } catch {
            XCTAssertEqual((error as NSError).code, PMEngineError.presetLoadFailed.rawValue)
        }
        for _ in 0..<10 { renderer.renderFrame() }
        XCTAssertGreaterThan(litPixels(renderer.readPixels()), 0)
    }

    func testPauseAndResumeTheDisplayLink() throws {
        let renderer = try makeLaidOut()
        // What the view reports when it joins and leaves a window (an app-less test has no scene
        // to create a window in).
        let layerView = try XCTUnwrap(renderer.view as? GLESLayerView)
        layerView.onWindowChange?(true)
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)
        renderer.pause()
        XCTAssertEqual(renderer.isDisplayLinkPaused, true)
        renderer.resume()
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)
        layerView.onWindowChange?(false)
        XCTAssertNil(renderer.isDisplayLinkPaused, "leaving the window stops the display link")
    }

}
