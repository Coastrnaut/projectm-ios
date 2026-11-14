// RecordingQualityUITests.swift — REC-005-T11 on the iOS Simulator: Settings → Recording quality lists
// Draft, Standard, High and Max with what each records, Standard selected by default; tapping High selects
// it. One short test (owner rule 7: under 30 s); persistence and disabled rows are proven by
// `RecordingQualityAppTests`. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecordingQualityUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func row(_ raw: String) -> XCUIElement { app.buttons["recordingQuality." + raw] }

    func testPickerSelectsAProfile() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        XCTAssertTrue(app.reveal(row("max")), "the four profiles are in Settings › Recording quality")
        for raw in ["draft", "standard", "high", "max"] {
            XCTAssertTrue(row(raw).exists, raw)
        }
        XCTAssertTrue(row("standard").isSelected, "Standard by default")
        XCTAssertFalse(row("high").isSelected)
        XCTAssertTrue(row("draft").label.hasPrefix("Draft, "), row("draft").label)
        XCTAssertTrue(row("draft").label.contains("H.264 · 4 Mb/s · 30 fps"), row("draft").label)
        XCTAssertTrue(row("high").isEnabled, "the simulator encodes HEVC: \(row("high").label)")
        row("high").tap()
        XCTAssertTrue(poll(5) { self.row("high").isSelected }, row("high").label)
        XCTAssertFalse(row("standard").isSelected)
    }
}
