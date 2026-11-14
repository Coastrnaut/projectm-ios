// SceneSnapshotUITests.swift — SCN-008-T12 (US1 scenario 3; SCN-008-R9, S5) on the iOS Simulator: on the Photo
// visual with Glow on, Settings › Snapshots › Save Snapshot, move Intensity, Recall: the slider's value label
// shows the saved value again, and the DEBUG media-load probe ("photo=… video=… logo=… host=…") is unchanged by
// the recall (no photo decode, video seek, logo upload or new visual instance). `-settings.visual photo` and
// `-settings.circularSpectrum.glow YES` (argument domain) and `-uitestSeedPhoto solid` set the scene up without
// taps (owner rule 7: under 30 s). Simulator results are never device evidence (Constitution X).
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

    func testSaveChangeRecallRestoresTheValueWithoutReloadingMedia() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSeedPhoto", "solid", "-settings.visual", "photo", "-settings.circularSpectrum.glow", "YES"]
            + Self.noStore
        app.launch()
        let photo = app.descendants(matching: .any)["photoVisual"].firstMatch
        XCTAssertTrue(photo.appears(within: 15), "the Photo visual is shown")
        XCTAssertTrue(poll(10) { (photo.value as? String) == "Photo 64 × 48" }, "the photo is loaded before the test")

        let area = app.otherElements["visualizerTapArea"].firstMatch
        if !app.buttons["settings"].appears(within: 1) { area.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let save = app.buttons["snapshotSave"]
        XCTAssertTrue(app.reveal(save), "the Snapshots section")
        save.tap()
        XCTAssertTrue(poll(5) { self.probe.label.hasSuffix("Saved Snapshot 1") }, "saved: \(probe.label)")
        XCTAssertTrue(app.staticTexts["snapshotRow.0"].exists || app.descendants(matching: .any)["snapshotRow.0"].exists)

        let intensity = app.slider("glowIntensitySlider")
        XCTAssertTrue(app.reveal(intensity, down: true))
        XCTAssertEqual(intensity.value as? String, "50 percent")
        intensity.dragSlider(from: 0.5, to: 1)
        XCTAssertTrue(poll(5) { (intensity.value as? String) == "100 percent" }, "moved: \(String(describing: intensity.value))")

        let recall = app.buttons["snapshotRecall.0"]
        XCTAssertTrue(app.reveal(recall))
        let before = mediaCounts
        XCTAssertTrue(before.hasPrefix("photo="), "probe: \(probe.label)")
        recall.tap()
        XCTAssertTrue(poll(5) { self.probe.label.hasSuffix("Recalled Snapshot 1") }, "recalled: \(probe.label)")
        XCTAssertEqual(mediaCounts, before, "the recall reloaded no media")

        XCTAssertTrue(app.reveal(intensity, down: true))
        XCTAssertTrue(poll(5) { (intensity.value as? String) == "50 percent" }, "restored: \(String(describing: intensity.value))")
    }
}
