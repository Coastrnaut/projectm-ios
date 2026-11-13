// MemoryPressureUITests.swift — PERF-006-T12 on the iOS Simulator: the roadmap acceptance "Injected
// warning drops cache usage and retains playable scene" (PERF-006-S1, S2) on projectM, the Camera
// stand-in (`-uitestCamera granted`) and Photo (`-uitestSeedPhoto solid`).
//
// The warning is injected with the DEBUG probe (`-uitestMemoryPressure`), which posts the notification
// UIKit posts for a real warning: the app's handling is real, the memory pressure is simulated.
// Simulator results are never device evidence (Constitution X); real pressure is PERF-006-T17.
// Waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class MemoryPressureUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestMemoryPressure",
                               "-autostart", "inAppPlayback"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func value(_ id: String) -> String? { app.staticTexts[id].value as? String }
    private func number(_ id: String) -> Int { Int(value(id) ?? "") ?? -1 }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func choose(_ title: String) {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow(title)
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func assertFramesAdvance(_ message: String) {
        XCTAssertTrue(poll(10) { self.number("visualFrames") > 0 }, "\(message): frames are shown")
        let first = number("visualFrames")
        XCTAssertTrue(poll(10) { self.number("visualFrames") > first }, "\(message): and keep coming (\(first) → \(number("visualFrames")))")
    }

    /// Injects one warning and checks the scene is retained: one recovery, the frames keep coming, the
    /// source was not restarted, no retired picture remains.
    private func injectAndAssertSceneRetained(_ message: String) {
        let recoveries = number("memoryRecoveries")
        app.buttons["memory:warning"].tap()
        XCTAssertTrue(poll(5) { self.number("memoryRecoveries") == recoveries + 1 }, "\(message): one recovery ran")
        XCTAssertGreaterThanOrEqual(number("memoryFreedBytes"), 0, "\(message): a report exists")
        XCTAssertTrue(poll(2) { self.value("memoryRetiredBytes") == "0" }, "\(message): no retired picture remains")
        assertFramesAdvance("\(message), after the warning")
        XCTAssertEqual(value("sourceStarts"), "1", "\(message): the source was not restarted")
    }

    /// projectM: the warning (and a critical signal) frees the warm-up's context; projectM keeps
    /// rendering and the source keeps playing.
    func testProjectMKeepsRenderingAfterAWarningAndACriticalSignal() {
        launch([])
        assertFramesAdvance("projectM")
        // The warm-up starts 2.5 s after the first preset's switch and keeps its context while idle.
        let heldContext = poll(8) { self.value("memoryWarmUpContext") == "yes" }
        injectAndAssertSceneRetained("projectM")
        XCTAssertEqual(value("memoryWarmUpContext"), "no", "the warm-up holds no context after the warning")
        print("PERF-006 evidence: projectM warm-up held its context before the warning: \(heldContext), freed \(number("memoryFreedBytes")) B")
        if heldContext {
            XCTAssertGreaterThanOrEqual(number("memoryFreedBytes"), 256 * 256 * 4, "the warm-up's target was freed (estimate)")
        }

        app.buttons["memory:critical"].tap()   // escalates: the warm-up is shed for the cool-down
        XCTAssertTrue(poll(5) { self.number("memoryRecoveries") == 2 })
        XCTAssertEqual(value("memoryWarmUpContext"), "no")
        assertFramesAdvance("projectM, after the critical signal")
        XCTAssertEqual(value("sourceStarts"), "1")
    }

    /// Camera (stand-in): the warning keeps the camera visual rendering.
    func testCameraKeepsRenderingAfterAWarning() {
        launch(["-uitestCamera", "granted"])
        choose("Camera")
        XCTAssertTrue(app.descendants(matching: .any)["cameraVisual"].firstMatch.appears(within: 10))
        assertFramesAdvance("Camera")
        injectAndAssertSceneRetained("Camera")
        XCTAssertTrue(app.descendants(matching: .any)["cameraVisual"].firstMatch.exists, "the chosen visual is still shown")
    }

    /// Photo: a rotation retires the old size's pictures; the warning frees them (> 0 bytes) and the
    /// photo keeps rendering.
    func testPhotoFreesRetiredPicturesAndKeepsRendering() {
        launch(["-uitestSeedPhoto", "solid"])
        choose("Photo")
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
        assertFramesAdvance("Photo")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(poll(10) { self.number("memoryRetiredBytes") > 0 }, "the rotation retired the old size's pictures")
        let retired = number("memoryRetiredBytes")
        injectAndAssertSceneRetained("Photo")
        XCTAssertGreaterThanOrEqual(number("memoryFreedBytes"), retired, "S1: the freed bytes include every retired picture")
        print("PERF-006 evidence: Photo retired \(retired) B before the warning, freed \(number("memoryFreedBytes")) B")
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.exists, "the chosen visual is still shown")
        XCUIDevice.shared.orientation = .portrait
    }
}
