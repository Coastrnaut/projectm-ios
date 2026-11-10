// Task T077: ANGLERenderer (ADR-0003 Option B) renders the engine's upstream test preset on the
// iOS Simulator through ANGLE's Metal backend. The view is laid out off screen, frames are rendered
// without presenting, and the window surface's framebuffer is read back.
import XCTest
import AudioCore
import ProjectMBridge
import Rendering
@testable import ANGLERendering

@MainActor
final class ANGLERendererTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private func preset(_ file: String) -> Preset {
        Preset(id: "tests/\(file)", name: file, fileURL: Self.testPresets.appendingPathComponent(file))
    }

    private func makeLaidOut(width: CGFloat = 64, height: CGFloat = 64) throws -> ANGLERenderer {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        renderer.view.layoutIfNeeded()
        return renderer
    }

    private func litPixels(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }.count
    }

    func testCreatesAWindowSurfaceAtTheDisplayScale() throws {
        let renderer = try makeLaidOut(width: 80, height: 40)
        XCTAssertTrue(renderer.hasWindowSurface)
        let scale = renderer.view.contentScaleFactor
        XCTAssertEqual(renderer.currentSurfaceSize.width, Int((80 * scale).rounded()))
        XCTAssertEqual(renderer.currentSurfaceSize.height, Int((40 * scale).rounded()))
    }

    func testRendersTheUpstreamTestPreset() async throws {
        let renderer = try makeLaidOut()
        try await renderer.setPreset(preset("100-square.milk"))
        for _ in 0..<30 { XCTAssertTrue(renderer.renderFrame(present: false)) }
        let pixels = renderer.readPixels()
        XCTAssertFalse(pixels.isEmpty, "read back the framebuffer")
        XCTAssertGreaterThan(litPixels(pixels), 0, "the preset drew something")
    }

    func testPresentsFramesAndDrainsTheReader() throws {
        let renderer = try makeLaidOut()
        let ring = NormalizedPCMRing()
        let samples = [Float](repeating: 0.25, count: 2 * 1_000)
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 1_000) }
        renderer.attach(pcm: ring)
        XCTAssertTrue(renderer.renderFrame(present: true))
        XCTAssertEqual(ring.availableFrames, max(0, 1_000 - Int(ProjectMEngine.maxSamplesPerFrame)))
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
        for _ in 0..<10 { renderer.renderFrame(present: false) }
        XCTAssertGreaterThan(litPixels(renderer.readPixels()), 0)
    }

    func testPauseAndResumeTheDisplayLink() throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)
        renderer.pause()
        XCTAssertEqual(renderer.isDisplayLinkPaused, true)
        renderer.resume()
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)
        layerView.onWindowChange?(false)
        XCTAssertNil(renderer.isDisplayLinkPaused)
    }
}
