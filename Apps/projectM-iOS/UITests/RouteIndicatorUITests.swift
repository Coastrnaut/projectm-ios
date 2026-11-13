// RouteIndicatorUITests.swift — AUD-007-T13: the roadmap acceptance, synthetic half, on the iOS
// Simulator: "Plug or unplug headphones; indicator changes without claiming a capture source."
//
// The app plays the reference track as In-App Playback with the real audio engine and session. The
// Debug launch hook `-uitestFakeRoutes` makes the route indicator read a fake route, and its buttons
// post the real route-change notification, so AUD-014's backend pauses on the unplug as on a device.
// Simulator only, never device evidence: the real plug and unplug is AUD-007-T16 {device}.
import XCTest

@MainActor
final class RouteIndicatorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var sourceIndicator: XCUIElement { app.staticTexts["sourceIndicator"] }
    private var routeIndicator: XCUIElement { app.descendants(matching: .any)["routeIndicator"].firstMatch }
    private var explanation: XCUIElement { app.staticTexts["routeExplanation"] }
    private var tapArea: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    /// The route indicator's VoiceOver label, showing the controls first if they hid.
    private func routeLabel() -> String {
        if !routeIndicator.exists { tapArea.tap() }
        XCTAssertTrue(routeIndicator.appears(within: 3), "the route indicator is in the controls")
        return routeIndicator.label
    }

    private func expectRoute(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(poll(5) { self.routeLabel() == label }, "route indicator \"\(routeIndicator.label)\", expected \"\(label)\"",
                      file: file, line: line)
    }

    private func expectExplanation(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(poll(3) { self.explanation.exists && self.explanation.label == text },
                      "explanation \"\(explanation.exists ? explanation.label : "none")\", expected \"\(text)\"", file: file, line: line)
    }

    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.appears(within: 5), id)
        button.tap()
    }

    func testPlugAndUnplugChangeTheIndicatorWithoutNamingACaptureSource() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestFakeRoutes"] + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 10))
        acknowledge.tap()
        let row = app.buttons["In-App Playback"]
        XCTAssertTrue(row.appears(within: 10))
        row.tap()
        XCTAssertTrue(poll(15) { self.sourceIndicator.exists && self.sourceIndicator.label.hasSuffix("· Active audio") },
                      "playing; source indicator \"\(sourceIndicator.label)\"")

        expectRoute("Audio output: Speaker")
        tap("route:wiredIn")
        expectExplanation("Now playing through Headphones")
        expectRoute("Audio output: Headphones")

        tap("route:wiredOut")
        expectExplanation("Headphones disconnected — paused")
        expectRoute("Audio output: Speaker")
        XCTAssertTrue(poll(5) { self.sourceIndicator.label.hasSuffix("· Paused") }, "AUD-014 paused: \"\(sourceIndicator.label)\"")

        // Constitution IV: no route text names a source mode or a capture.
        for text in [routeIndicator.label, explanation.exists ? explanation.label : ""] {
            for word in ["System/App Capture", "Microphone", "In-App Playback", "captur"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(word), "\"\(text)\" names \"\(word)\"")
            }
        }
    }
}
