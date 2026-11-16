// ColorSamplerUITests.swift — UIX-012-T09 on the iOS Simulator (S4; R1, R3, R8, R11): the Text visual, Settings ›
// Text, the eyedropper by Color, then a tap on the preview. The DEBUG fixture `-uitestColorSampleFixture 51,102,153`
// makes the shown visual's capture a solid colour (research UIX-012-D7; the GPU path is proven by
// ColorSampleCompositorTests). Settings closes for sampling and comes back with the eyedropper reading the sampled
// colour. Under 30 s (owner rule 7). Simulator results are UI evidence only (Constitution X).
import UIKit
import XCTest

@MainActor
final class ColorSamplerUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func value(_ element: XCUIElement) -> String { (element.value as? String) ?? "" }

    func testEyedropperThenTapWritesTheFixtureColour() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-settings.visual", "text",
                               "-uitestColorSampleFixture", "51,102,153",
                               "-uitestSettingsSection", "text", "-uitestSettingsSectionOnce"] + Self.noStore
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let eyedropper = app.buttons["eyedropper.textColor"].firstMatch
        XCTAssertTrue(app.reveal(eyedropper), "the eyedropper by the text Color")
        XCTAssertEqual(eyedropper.label, "Pick Text color from the picture")
        XCTAssertEqual(value(eyedropper), "red 100%, green 100%, blue 100%", "white by default")
        eyedropper.tap()

        let banner = app.staticTexts["colorSamplingBanner"].firstMatch
        XCTAssertTrue(banner.appears(within: 5), "the sampling banner over the preview")
        XCTAssertEqual(banner.label, "Tap the picture to pick Text color.")
        // A Settings sheet closes for the sample; on an iPad Settings stays beside the scaled preview (UIX-012 User
        // Story 2, the split editor; seen on D2, 2026-11-15).
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.navigationBars["Settings"].exists, "Settings stays beside the preview (split editor)")
        } else {
            XCTAssertFalse(app.navigationBars["Settings"].exists, "the Settings sheet gave way to the preview")
        }
        let layer = app.descendants(matching: .any)["colorSamplingLayer"].firstMatch
        let probe = app.staticTexts["splitOutputFrame"]
        let slot: [Double] = ((probe.exists ? probe.value as? String : nil) ?? "").split(separator: "|").first
            .map { $0.split(separator: ",").compactMap { Double($0) } } ?? []
        if UIDevice.current.userInterfaceIdiom == .pad, slot.count == 4 {
            // The split editor: tap the middle of the scaled preview (the slot), not the layer's middle, which can be
            // in the pane's margin or under Settings, where a tap is rejected as outside the picture (UIX-012).
            app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: slot[0] + slot[2] / 2, dy: slot[1] + slot[3] / 2)).tap()
        } else {
            layer.tap()
        }

        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5), "Settings returns after the sample")
        XCTAssertFalse(banner.exists, "one sample ends sampling mode")
        let again = app.buttons["eyedropper.textColor"].firstMatch
        XCTAssertTrue(app.reveal(again))
        XCTAssertEqual(value(again), "red 20%, green 40%, blue 60%", "the text colour is the sampled fixture colour")
    }
}
