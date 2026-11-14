// SceneSnapshotUITests.swift — SCN-008-T12 (US1 scenario 3; SCN-008-R9, S5) on the iOS Simulator: with Glow on,
// Settings › Snapshots › Save Snapshot, move Intensity, Recall: the slider's value label shows the saved value
// again, and the DEBUG media-load probe ("photo=… video=… logo=… host=…") is unchanged by the recall (no photo
// decode, video seek, logo upload or new visual instance). Settings shows the glow controls for the native visuals
// only, so the test runs on the Circular Spectrum with a stored photo (`-uitestSeedPhoto solid`); the Photo visual
// case is SceneSnapshotAcceptanceTests. `-settings.visual circularSpectrum` (argument domain) sets the visual
// without taps (owner rule 7: under 30 s). Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class SceneSnapshotUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: XCUIElement { app.staticTexts["snapshotMediaProbe"] }

    /// "photo=1 video=0 logo=0 host=1" (the part before " | ").
    private var mediaCounts: String {
        String(probe.label.split(separator: "|").first ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// On screen below the navigation bar (one frame read; `reveal` only when it is not).
    private func onScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame, screen = app.windows.firstMatch.frame
        return frame.height > 0 && frame.minY >= app.navigationBars.firstMatch.frame.maxY && frame.maxY <= screen.maxY
    }

    func testSaveChangeRecallRestoresTheValueWithoutReloadingMedia() {
        XCUIDevice.shared.orientation = .portrait
        // Extra-small text keeps the glow sliders and the Snapshots rows on about one screen (fewer drags).
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSeedPhoto", "solid", "-settings.visual", "circularSpectrum",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXS"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15), "the Circular Spectrum is shown")

        let area = app.otherElements["visualizerTapArea"].firstMatch
        if !app.buttons["settings"].appears(within: 1) { area.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let glow = app.switches["glowToggle"]
        XCTAssertTrue(glow.appears(within: 2) || app.reveal(glow), "the Glow toggle")
        if (glow.value as? String) != "1" { glow.switches.firstMatch.exists ? glow.switches.firstMatch.tap() : glow.tap() }
        let intensity = app.slider("glowIntensitySlider")
        XCTAssertTrue(intensity.appears(within: 2), "Glow is on")
        XCTAssertEqual(intensity.value as? String, "50 percent")

        let save = app.buttons["snapshotSave"]
        XCTAssertTrue(onScreen(save) || app.reveal(save), "the Snapshots section")
        save.tap()
        XCTAssertTrue(onScreen(probe) || app.reveal(probe), "the probe under the list")
        XCTAssertTrue(poll(5) { self.probe.label.hasSuffix("Saved Snapshot 1") }, "saved: \(probe.label)")

        XCTAssertTrue(onScreen(intensity) || app.reveal(intensity, down: true))
        intensity.dragSlider(from: 0.5, to: 1)
        XCTAssertTrue(poll(5) { (intensity.value as? String) == "100 percent" }, "moved: \(String(describing: intensity.value))")

        let recall = app.buttons["snapshotRecall.0"]
        XCTAssertTrue(onScreen(recall) || app.reveal(recall))
        XCTAssertTrue(probe.exists || app.reveal(probe))
        let before = mediaCounts
        XCTAssertTrue(before.hasPrefix("photo="), "probe: \(probe.label)")
        recall.tap()
        XCTAssertTrue(poll(5) { self.probe.label.hasSuffix("Recalled Snapshot 1") }, "recalled: \(probe.label)")
        XCTAssertEqual(mediaCounts, before, "the recall reloaded no media")

        XCTAssertTrue(intensity.exists || app.reveal(intensity, down: true))
        XCTAssertTrue(poll(5) { (intensity.value as? String) == "50 percent" }, "restored: \(String(describing: intensity.value))")
    }
}
