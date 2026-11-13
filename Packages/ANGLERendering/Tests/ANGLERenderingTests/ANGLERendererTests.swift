// Task T077: ANGLERenderer (ADR-0003 Option B) renders the engine's upstream test preset on the
// iOS Simulator through ANGLE's Metal backend. The view is laid out off screen, frames are rendered
// without presenting, and the window surface's framebuffer is read back.
import XCTest
import AudioCore
import PresentationLifecycle
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

    /// Renders frames (not presented) until the preset has lit pixels. A preset's first frames
    /// after loading are black for a time that depends on the wall clock, so tests that need a
    /// drawn picture drive frames until there is one, for at most 3 s. Returns the lit-pixel count.
    @discardableResult
    private func renderUntilLit(_ renderer: ANGLERenderer) async throws -> Int {
        // Bounded by time (30 s), not by a frame count that assumed the Mac's GPU speed.
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            XCTAssertTrue(renderer.renderFrame(present: false))
            let lit = litPixels(renderer.readPixels())
            if lit > 0 { return lit }
            try await Task.sleep(for: .milliseconds(10))
        }
        return 0
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

    /// Feature 002 SC-104: upcoming presets are warmed on a background thread with its own context;
    /// the visible engine then switches to one and still draws, and a newer request replaces the queue.
    func testPrewarmRunsInTheBackgroundAndTheSwitchStillDraws() async throws {
        let renderer = try makeLaidOut()
        renderer.prewarmDelay = .zero
        try await renderer.setPreset(preset("100-square.milk"))
        renderer.prewarm([preset("110-per_pixel.milk"), preset("200-wave.milk")])
        // Wait for the warm-up with a 90 s ceiling. It took well under 5 s on the Mac Studio, but CI's
        // simulator has no GPU and warmed nothing within 5 s (run 43415519311), so the old 200 x 25 ms
        // budget failed there without a defect. The test checks that warming happens, not its speed.
        let deadline = ContinuousClock.now + .seconds(90)
        while renderer.prewarmedCount < 2 && ContinuousClock.now < deadline {
            renderer.renderFrame(present: false)   // the visible engine keeps drawing meanwhile
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(renderer.prewarmedCount, 2)
        renderer.prewarm([preset("200-wave.milk")])   // already warmed: skipped
        try await renderer.setPreset(preset("110-per_pixel.milk"))
        for _ in 0..<30 { XCTAssertTrue(renderer.renderFrame(present: false)) }
        XCTAssertGreaterThan(litPixels(renderer.readPixels()), 0, "the warmed preset draws")
        XCTAssertEqual(renderer.prewarmedCount, 2)
    }

    /// A newer request before the delay ends replaces the older one, so a fast run of switches warms
    /// only the latest candidates.
    func testPrewarmWaitsForTheDelayAndANewerRequestWins() async throws {
        let renderer = try makeLaidOut()
        renderer.prewarmDelay = .milliseconds(300)
        renderer.prewarm([preset("110-per_pixel.milk")])
        renderer.prewarm([preset("200-wave.milk")])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(renderer.prewarmedCount, 0, "nothing before the delay")
        let deadline = ContinuousClock.now + .seconds(90)   // a ceiling, not a speed target (CI has no GPU)
        while renderer.prewarmedCount < 1 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(renderer.prewarmedCount, 1, "only the newer request")
    }

    func testPrewarmCanBeTurnedOff() async throws {
        let renderer = try makeLaidOut()
        renderer.prewarmEnabled = false
        renderer.prewarm([preset("110-per_pixel.milk")])
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(renderer.prewarmedCount, 0)
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

    // MARK: - PERF-011: presentation suspension (R5, R6, R13; S1-S4)

    func testListsTheFrameLoopThenTheWarmUpAsPresentationResources() throws {
        let renderer = try makeLaidOut()
        let resources = renderer.presentationResources
        XCTAssertEqual(resources.count, 2)
        XCTAssertTrue(resources[0] === renderer)
        XCTAssertTrue(resources[1] === renderer.warmUp)
        XCTAssertEqual(resources.map(\.presentationResourceName), ["ANGLE frame loop and surface", "preset warm-up"])
    }

    func testSuspensionStopsTheLoopAndReleasesTheSurface() async throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        try await renderer.setPreset(preset("100-square.milk"))
        XCTAssertTrue(renderer.renderFrame(present: true))
        let presented = renderer.presentedFrameCount

        renderer.suspendForPresentationLoss()
        renderer.suspendForPresentationLoss()   // repeat: nothing
        XCTAssertTrue(renderer.isPresentationSuspended)
        XCTAssertNil(renderer.isDisplayLinkPaused, "S1: no display link")
        XCTAssertFalse(renderer.hasWindowSurface, "S2: the window surface is released")
        XCTAssertEqual(renderer.currentSurfaceSize.width, 0)
        XCTAssertFalse(renderer.renderFrame(present: true), "S1: no frame is drawn")
        XCTAssertFalse(renderer.renderFrame(present: false))
        XCTAssertEqual(renderer.timedFrames(3, reduceFlashing: false), [])
        XCTAssertEqual(renderer.readPixels(), [])
        XCTAssertEqual(renderer.presentedFrameCount, presented)
    }

    func testNothingRestartsTheLoopOrTheSurfaceWhileSuspended() async throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        renderer.suspendForPresentationLoss()

        renderer.resume()   // a source start or a user toggle
        XCTAssertNil(renderer.isDisplayLinkPaused)
        renderer.pause()
        renderer.resume()
        layerView.onWindowChange?(false)   // the view leaves and joins a window
        layerView.onWindowChange?(true)
        XCTAssertNil(renderer.isDisplayLinkPaused, "joining a window starts no loop")
        renderer.view.frame = CGRect(x: 0, y: 0, width: 96, height: 48)   // a system layout pass
        renderer.view.setNeedsLayout()
        renderer.view.layoutIfNeeded()
        XCTAssertFalse(renderer.hasWindowSurface, "layout creates no surface")
        try await renderer.setPreset(preset("110-per_pixel.milk"))   // a load that was in flight
        renderer.setTextureSearchPaths([])
        XCTAssertFalse(renderer.hasWindowSurface)
        XCTAssertFalse(renderer.renderFrame(present: false))
    }

    func testResumeRecreatesTheSurfaceAndKeepsThePreset() async throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        try await renderer.setPreset(preset("100-square.milk"))
        let lit1 = try await renderUntilLit(renderer)
        XCTAssertGreaterThan(lit1, 0, "the preset draws before the suspension")
        let size = renderer.currentSurfaceSize

        renderer.suspendForPresentationLoss()
        renderer.resumeForPresentation()
        renderer.resumeForPresentation()   // repeat: nothing
        XCTAssertFalse(renderer.isPresentationSuspended)
        XCTAssertTrue(renderer.hasWindowSurface)
        XCTAssertEqual(renderer.currentSurfaceSize.width, size.width)
        XCTAssertEqual(renderer.currentSurfaceSize.height, size.height)
        XCTAssertEqual(renderer.isDisplayLinkPaused, false, "the loop is back, once")
        // The engine and its preset were kept: frames light pixels without loading anything.
        for _ in 0..<5 { XCTAssertTrue(renderer.renderFrame(present: false)) }
        XCTAssertGreaterThan(litPixels(renderer.readPixels()), 0, "S3: the same preset draws")
        XCTAssertTrue(renderer.renderFrame(present: true))
    }

    func testAUserPauseSurvivesSuspension() throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        renderer.pause()
        renderer.suspendForPresentationLoss()
        renderer.resumeForPresentation()
        XCTAssertEqual(renderer.isDisplayLinkPaused, true, "FR-046: paused by the user stays paused")
        XCTAssertTrue(renderer.hasWindowSurface, "the surface is ready for the user's resume")
        renderer.resume()
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)

        // Paused during the suspension.
        renderer.suspendForPresentationLoss()
        renderer.pause()
        renderer.resumeForPresentation()
        XCTAssertEqual(renderer.isDisplayLinkPaused, true)
    }

    func testResumeOutsideAWindowStartsNoLoop() throws {
        let renderer = try makeLaidOut()
        renderer.suspendForPresentationLoss()
        renderer.resumeForPresentation()
        XCTAssertNil(renderer.isDisplayLinkPaused)
        XCTAssertTrue(renderer.hasWindowSurface)
    }

    func testASizeChangeWhileSuspendedAppliesOnResume() async throws {
        let renderer = try makeLaidOut(width: 64, height: 64)
        try await renderer.setPreset(preset("100-square.milk"))
        renderer.suspendForPresentationLoss()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 80, height: 40)   // rotated while away
        renderer.view.layoutIfNeeded()
        renderer.resumeForPresentation()
        let scale = renderer.view.contentScaleFactor
        XCTAssertEqual(renderer.currentSurfaceSize.width, Int((80 * scale).rounded()))
        XCTAssertEqual(renderer.currentSurfaceSize.height, Int((40 * scale).rounded()))
        let lit2 = try await renderUntilLit(renderer)
        XCTAssertGreaterThan(lit2, 0, "the preset draws at the new size")
    }

    /// The limiter is exercised with solid frames, whose luminance is exact. The engine's picture
    /// is not used for values here: the test preset's brightness varies with wall-clock time, and a
    /// very dark frame stays under the lit-pixel threshold once it goes through the limiter.
    func testReduceFlashingTargetIsReleasedAndWorksAgainAfterResume() async throws {
        let renderer = try makeLaidOut()
        try await renderer.setPreset(preset("100-square.milk"))
        renderer.reduceFlashing = true
        for _ in 0..<5 { XCTAssertTrue(renderer.renderFrame(present: false)) }
        XCTAssertTrue(renderer.hasFlashLimiter)
        // Leave the envelope's history at white, so a stale state would be visible after the resume.
        XCTAssertNotNil(renderer.limitedSolidFrame(1, 1.0 / 60))

        renderer.suspendForPresentationLoss()
        XCTAssertFalse(renderer.hasFlashLimiter, "R6: the Reduce-flashing target is released")
        XCTAssertNil(renderer.flashLimiterGain)
        XCTAssertNil(renderer.limitedSolidFrame(1, 1.0 / 60), "nothing is drawn while suspended")
        XCTAssertFalse(renderer.hasFlashLimiter, "and nothing recreates the target")
        renderer.reduceFlashing = false   // toggled in the background: nothing to reset, no crash
        renderer.reduceFlashing = true

        renderer.resumeForPresentation()
        // The engine's frames go through a new limiter onto the new surface.
        for _ in 0..<5 { XCTAssertTrue(renderer.renderFrame(present: false)) }
        XCTAssertTrue(renderer.hasFlashLimiter, "recreated on the first limited frame")
        let gain = try XCTUnwrap(renderer.flashLimiterGain)
        XCTAssertGreaterThanOrEqual(gain, 0)
        XCTAssertLessThanOrEqual(gain, 1)
        let size = renderer.currentSurfaceSize
        XCTAssertEqual(renderer.readPixels().count, size.width * size.height * 4, "the output reaches the new surface")

        // And it limits (FX-019: amended from T104's ramp): black, then a cut to white rises at
        // 0.25 per second (0.025 per 0.1 s frame), visible on the surface.
        XCTAssertEqual(try XCTUnwrap(renderer.limitedSolidFrame(0, 0.1)), 1, accuracy: 0.01, "black needs no gain")
        XCTAssertEqual(litPixels(renderer.readPixels()), 0)
        XCTAssertEqual(try XCTUnwrap(renderer.limitedSolidFrame(1, 0.1)), 0.025, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(renderer.limitedSolidFrame(1, 0.1)), 0.05, accuracy: 0.002)
        let pixels = renderer.readPixels()
        XCTAssertEqual(litPixels(pixels), size.width * size.height, "every pixel shows the limited frame")
        // Relative luminance 0.05 is an sRGB-encoded value of 63 of 255.
        XCTAssertEqual(Double(pixels[0]), 63, accuracy: 3)
    }

    /// A new limiter starts from its first frame's brightness, also after a suspension: no ramp up
    /// from black and no value left over from before. (FX-019: a following black frame stays
    /// black; T104 lifted it with gray.)
    func testTheLimiterStartsOverAfterASuspension() throws {
        let renderer = try makeLaidOut()
        renderer.reduceFlashing = true
        XCTAssertEqual(try XCTUnwrap(renderer.limitedSolidFrame(0, 1.0 / 60)), 1, accuracy: 0.01)
        renderer.suspendForPresentationLoss()
        renderer.resumeForPresentation()
        XCTAssertEqual(try XCTUnwrap(renderer.limitedSolidFrame(1, 1.0 / 60)), 1, accuracy: 0.01,
                       "the first frame after the resume is shown at its own brightness")
        renderer.limitedSolidFrame(0, 1.0 / 60)
        XCTAssertEqual(litPixels(renderer.readPixels()), 0, "never brighter than the input")
    }

    func testTenFlipsEndInAWorkingRenderer() async throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        try await renderer.setPreset(preset("100-square.milk"))
        for _ in 0..<10 {
            renderer.suspendForPresentationLoss()
            XCTAssertFalse(renderer.hasWindowSurface)
            renderer.resumeForPresentation()
            XCTAssertTrue(renderer.renderFrame(present: false))
        }
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)
        let lit3 = try await renderUntilLit(renderer)
        XCTAssertGreaterThan(lit3, 0)
    }

    func testARegistryDrivesBothResourcesInOrder() async throws {
        let renderer = try makeLaidOut()
        let layerView = try XCTUnwrap(renderer.view as? MetalLayerView)
        layerView.onWindowChange?(true)
        let registry = PresentationResourceRegistry()
        renderer.presentationResources.forEach(registry.register)
        XCTAssertEqual(registry.activeCount, 2)

        let lost = registry.setCanPresent(false)
        XCTAssertEqual(lost, PresentationTransitionReport(canPresent: false, registered: 2, activeBefore: 2, activeAfter: 0))
        XCTAssertTrue(renderer.isPresentationSuspended)
        XCTAssertTrue(renderer.warmUp.isSuspended)
        XCTAssertFalse(renderer.hasWindowSurface)

        let regained = registry.setCanPresent(true)
        XCTAssertEqual(regained?.activeAfter, 2)
        XCTAssertFalse(renderer.isPresentationSuspended)
        XCTAssertFalse(renderer.warmUp.isSuspended)
        XCTAssertTrue(renderer.renderFrame(present: false))
    }

    func testARendererCreatedWhileTheAppCannotPresentStartsSuspended() throws {
        let registry = PresentationResourceRegistry()
        registry.setCanPresent(false)
        let renderer = try ANGLERenderer.make()
        renderer.presentationResources.forEach(registry.register)
        renderer.view.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        renderer.view.layoutIfNeeded()
        (renderer.view as? MetalLayerView)?.onWindowChange?(true)
        XCTAssertFalse(renderer.hasWindowSurface)
        XCTAssertNil(renderer.isDisplayLinkPaused)
        registry.setCanPresent(true)
        XCTAssertTrue(renderer.hasWindowSurface)
        XCTAssertEqual(renderer.isDisplayLinkPaused, false)
    }

    func testDestroyingASuspendedRendererIsSafe() async throws {
        var renderer: ANGLERenderer? = try makeLaidOut()
        try await renderer?.setPreset(preset("100-square.milk"))
        renderer?.reduceFlashing = true
        renderer?.renderFrame(present: false)
        renderer?.prewarmDelay = .zero
        renderer?.prewarm([preset("110-per_pixel.milk")])
        renderer?.presentationResources.reversed().forEach { $0.suspendForPresentationLoss() }
        weak let released = renderer
        renderer = nil
        XCTAssertNil(released, "R13: released without touching what it already released")
    }
}
