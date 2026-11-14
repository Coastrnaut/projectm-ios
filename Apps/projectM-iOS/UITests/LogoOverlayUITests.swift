// LogoOverlayUITests.swift — MED-010-T14 on the iOS Simulator (MED-010-S7, R5, R14): a seeded logo
// (`-uitestSeedLogo`: the real logo import, PNG with an alpha gradient) is drawn by the Text visual's logo
// layer: the DEBUG probe `logoProbe` ("drawn=<frames> logo=<yes|no>") counts frames that showed it. System
// pickers cannot be automated; the real picker is a device task (T25). Simulator results are never device
// evidence (Constitution X). Waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class LogoOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String { app.staticTexts["logoProbe"].value as? String ?? "" }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testTheSeededLogoIsDrawnOverTheTextVisual() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestSeedLogo"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.staticTexts["logoProbe"].appears(within: 5))
        XCTAssertTrue(probe.hasSuffix("logo=yes"), "the seed stored a logo: \(probe)")
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Text")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))

        let drawn: Bool = poll(15) { () -> Bool in Self.frames(self.probe) > 0 }
        XCTAssertTrue(drawn, "the Text visual's logo layer showed the logo: \(probe)")
        XCTAssertFalse(app.staticTexts["logoNotice"].exists, "no notice")
    }

    /// The `n` of "drawn=<n> logo=…" (-1 when unreadable).
    nonisolated static func frames(_ probe: String) -> Int {
        guard let start = probe.range(of: "drawn="), let end = probe.range(of: " logo=") else { return -1 }
        return Int(probe[start.upperBound..<end.lowerBound]) ?? -1
    }
}
