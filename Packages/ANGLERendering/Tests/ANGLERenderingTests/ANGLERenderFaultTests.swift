// PERF-014-T09 (preset load failures) and T14 (presentation failures) on the iOS Simulator: projectM's
// render health record. Faults come from the renderer's DEBUG `faultInjection` (a preset load fails as
// a shader that does not compile; the swap result reads as failed) and from a real unloadable preset.
// Ticks are driven by calling `presentationTick()` directly (the display link's path); no wall clock.
import XCTest
import Compositor
import ProjectMBridge
import Rendering
@testable import ANGLERendering

@MainActor
final class ANGLERenderFaultTests: XCTestCase {
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    private func preset(_ file: String) -> Preset {
        Preset(id: "tests/\(file)", name: file, fileURL: Self.testPresets.appendingPathComponent(file))
    }

    private func makeLaidOut() throws -> ANGLERenderer {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        renderer.view.layoutIfNeeded()
        return renderer
    }

    func testAnInjectedPresetLoadFailureIsRecordedAndRethrown() async throws {
        let renderer = try makeLaidOut()
        var reported: [RenderHealth] = []
        renderer.onRenderHealthChange = { (health: RenderHealth) in reported.append(health) }
        try await renderer.setPreset(preset("100-square.milk"))
        renderer.faultInjection.failPresetLoads = 1
        do {
            try await renderer.setPreset(preset("101-per_frame.milk"))
            XCTFail("the injected load must fail")
        } catch {
            XCTAssertEqual((error as NSError).domain, PMEngineErrorDomain, "the bridge's own error domain (FR-045 path)")
        }
        XCTAssertEqual(renderer.health.lastReason, .presetLoadFailed)
        XCTAssertEqual(renderer.health.faultCount, 1)
        XCTAssertEqual(renderer.health.state, .healthy, "R8: the previous preset keeps playing")
        XCTAssertEqual(reported.count, 1, "one report per change")
        try await renderer.setPreset(preset("101-per_frame.milk"))   // the injection was for one load
        XCTAssertEqual(renderer.health.faultCount, 1)
        XCTAssertTrue(renderer.presentationTick(), "frames keep coming")
    }

    func testARealUnloadablePresetRecordsTheSameReason() async throws {
        let renderer = try makeLaidOut()
        var bad = preset("broken.milk")
        bad.data = Data([0xFF, 0xFE, 0x00, 0x01])   // not a preset
        do {
            try await renderer.setPreset(bad)
            // projectM accepts some garbage as an empty preset; only a thrown load counts.
        } catch {
            XCTAssertEqual(renderer.health.lastReason, .presetLoadFailed)
            XCTAssertEqual(renderer.health.faultCount, 1)
            return
        }
        XCTAssertEqual(renderer.health.faultCount, 0, "no fault without a failed load")
    }

    func testAFailedSwapBacksOffRecreatesTheSurfaceAndEndsOnThePlaceholder() throws {
        let renderer = try makeLaidOut()
        renderer.recoveryPolicy = RenderRecoveryPolicy(firstDelayTicks: 3, maxRetries: 4)   // short; the standard ticks are RenderHealthTests'
        renderer.faultInjection.failPresentation = true
        XCTAssertFalse(renderer.presentationTick(), "tick 1: the swap fails")
        XCTAssertEqual(renderer.health.lastReason, .presentationFailed)
        XCTAssertEqual(renderer.health.state, .recovering)
        let presented = renderer.presentedFrameCount
        var rendered: [UInt64] = []
        while renderer.displayTicks < 46 + 100 {
            let before = renderer.health.faultCount
            renderer.presentationTick()
            if renderer.health.faultCount > before { rendered.append(renderer.displayTicks) }
        }
        XCTAssertEqual(rendered, [4, 10, 22, 46], "S3: renders only at the retry ticks (3, 6, 12, 24 apart)")
        XCTAssertEqual(renderer.health.state, .placeholder, "after the last failed retry")
        XCTAssertEqual(renderer.health.faultCount, 5)
        XCTAssertEqual(renderer.presentedFrameCount, presented, "nothing presented")
        XCTAssertTrue(renderer.hasWindowSurface, "each retry recreated the window surface")
        XCTAssertEqual(renderer.displayTicks, 146, "S2: ticks advance while faulted")

        renderer.faultInjection.failPresentation = false
        for _ in 0..<10 { renderer.presentationTick() }
        XCTAssertEqual(renderer.health.state, .placeholder, "no automatic return after giving up")
        renderer.resume()   // R6: the user resumes (or the visual is shown again)
        XCTAssertTrue(renderer.presentationTick(), "presented again after the reset")
        XCTAssertEqual(renderer.health.state, .healthy)
        XCTAssertEqual(renderer.health.recoveries, 1)
    }

    func testTheSwapRecoversAtTheNextRetryWhenTheFaultClears() throws {
        let renderer = try makeLaidOut()
        renderer.faultInjection.failPresentation = true
        renderer.presentationTick()
        renderer.faultInjection.failPresentation = false
        var presentedAt: UInt64?
        while renderer.displayTicks < 40, presentedAt == nil {
            if renderer.presentationTick() { presentedAt = renderer.displayTicks }
        }
        XCTAssertEqual(presentedAt, 31, "S4: the retry at tick 31 succeeds")
        XCTAssertEqual(renderer.health.state, .healthy)
        XCTAssertEqual(renderer.health.recoveries, 1)
    }
}
