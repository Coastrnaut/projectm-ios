// SlideshowUITests.swift — MED-006-T12 on the iOS Simulator (MED-006-S8, R15): five seeded pictures
// (`-uitestSeedPhoto slideshow5`: the real slideshow import, Slideshow on, Time 2 s) cycle in the saved
// order on the Photo visual: the DEBUG probe `slideshowProbe` ("<shown index> changes=<n>") advances
// 0 → 1 → 2. System pickers cannot be automated; the real multi-select picker is a device task (T22).
// Simulator results are never device evidence (Constitution X). Waits are ceilings for a slow shared
// Mac, never frame budgets.
import XCTest

@MainActor
final class SlideshowUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String { app.staticTexts["slideshowProbe"].value as? String ?? "" }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testFiveSeededPicturesCycleInTheSavedOrder() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSeedPhoto", "slideshow5"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Photo")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))

        XCTAssertTrue(app.staticTexts["slideshowProbe"].appears(within: 10), "the Photo visual runs the slideshow")
        // Every reading must pair the shown position with the change count (index = changes mod 5: the
        // saved order, no skips); at least three changes within the ceiling.
        var seen: [String] = []
        let reached: Bool = poll(20) { () -> Bool in
            let value: String = self.probe
            if seen.last != value { seen.append(value) }
            return Self.changes(value) >= 3
        }
        XCTAssertTrue(reached, "three changes at 2 s each: \(seen)")
        for value in seen where !value.isEmpty {
            let parts: [Substring] = value.split(separator: " ")
            let index: Int = Int(parts.first ?? "") ?? -1
            XCTAssertEqual(index, Self.changes(value) % 5, "in order: \(value) of \(seen)")
        }
        XCTAssertTrue(seen.contains("1 changes=1") || seen.contains("2 changes=2"), "the positions advance one by one: \(seen)")
        XCTAssertFalse(app.otherElements["photoNotice"].exists, "no notice")
    }

    /// The `n` of "<index> changes=<n>" (-1 when unreadable).
    nonisolated static func changes(_ probe: String) -> Int {
        guard let range = probe.range(of: "changes=") else { return -1 }
        return Int(probe[range.upperBound...]) ?? -1
    }
}
