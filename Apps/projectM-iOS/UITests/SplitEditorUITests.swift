// SplitEditorUITests.swift — UIX-007-T10, T11 on an iPad simulator (specs/205-uix-007-split-preview-
// editor; UIX-007-S2). Settings opens beside the live output; dragging the divider changes the output's
// on-screen size but never its aspect ratio, read from UIKit through the DEBUG `splitOutputFrame` probe
// ("x,y,w,h|W,H|bw,bh": the device slot's frame in the window, the window's size, the slot's bounds).
// Skipped in compact width (iPhone keeps the sheet; SettingsUITests covers it). Simulator results are
// never device evidence (UIX-007-T13 is the D2 pass). Owner rule 7: each test < 30 s.
import XCTest

@MainActor
final class SplitEditorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private struct Probe {
        let frame: CGRect
        let window: CGSize
        let bounds: CGSize
        var aspect: Double { Double(frame.width / frame.height) }
        var windowAspect: Double { Double(window.width / window.height) }
    }

    private var divider: XCUIElement { app.descendants(matching: .any)["splitEditorDivider"].firstMatch }
    private var pane: XCUIElement { app.descendants(matching: .any)["splitEditorPane"].firstMatch }

    private func launch() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSplitEditorWidth", "400"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func probe(file: StaticString = #filePath, line: UInt = #line) -> Probe? {
        let element = app.staticTexts["splitOutputFrame"]
        XCTAssertTrue(element.appears(within: 3), "probe", file: file, line: line)
        let groups: [[Double]] = ((element.value as? String) ?? "").split(separator: "|").map { (part: Substring) -> [Double] in
            part.split(separator: ",").compactMap { (s: Substring) -> Double? in Double(s) }
        }
        guard groups.count == 3, groups[0].count == 4, groups[1].count == 2, groups[2].count == 2 else {
            XCTFail("probe value \(element.value ?? "nil")", file: file, line: line)
            return nil
        }
        return Probe(frame: CGRect(x: groups[0][0], y: groups[0][1], width: groups[0][2], height: groups[0][3]),
                     window: CGSize(width: groups[1][0], height: groups[1][1]),
                     bounds: CGSize(width: groups[2][0], height: groups[2][1]))
    }

    /// Waits for the output to settle (the snap animates for 0.2 s), then checks it (UIX-007-R3, R4).
    @discardableResult
    private func assertUndistorted(inside paneMaxX: CGFloat?, file: StaticString = #filePath, line: UInt = #line) -> Probe? {
        var last: Probe?
        _ = poll(2) {
            let next = self.probe(file: file, line: line)
            defer { last = next }
            return next != nil && next?.frame == last?.frame
        }
        guard let p = last else { return nil }
        XCTAssertEqual(p.aspect, p.windowAspect, accuracy: p.windowAspect * 0.01, "output aspect \(p.frame) vs window \(p.window)", file: file, line: line)
        XCTAssertEqual(p.bounds, p.window, "the visual itself keeps the window's size (not re-laid out)", file: file, line: line)
        if let paneMaxX {
            XCTAssertGreaterThanOrEqual(p.frame.minX, -0.5, file: file, line: line)
            XCTAssertLessThanOrEqual(p.frame.maxX, paneMaxX + 0.5, "inside the output pane", file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.frame.minY, -0.5, file: file, line: line)
            XCTAssertLessThanOrEqual(p.frame.maxY, p.window.height + 0.5, file: file, line: line)
        }
        return p
    }

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap() }
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    /// R9: the controls (shown by the drag's touch or still up) lie in the output pane, the divider on screen.
    private func assertControlsInPane(file: StaticString = #filePath, line: UInt = #line) {
        let window: CGRect = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(divider.frame.maxX, window.maxX + 0.5, "the divider stays on screen", file: file, line: line)
        let controls = app.otherElements["controls"]
        if controls.exists {
            XCTAssertLessThanOrEqual(controls.frame.maxX, divider.frame.minX + 0.5, "controls \(controls.frame)", file: file, line: line)
        }
    }

    /// UIX-007-S2: open → split; drag wider → smaller output, same aspect; Done → full window.
    func testDraggingTheDividerNeverDistortsTheOutput() throws {
        launch()
        guard app.windows.firstMatch.horizontalSizeClass == .regular else {
            throw XCTSkip("compact width: Settings is a sheet (SettingsUITests)")
        }
        let full: Probe? = assertUndistorted(inside: nil)
        XCTAssertEqual(full?.frame.width ?? 0, full?.window.width ?? -1, accuracy: 0.5, "full screen before editing")
        openSettings()
        XCTAssertTrue(pane.appears(within: 3), "Settings is beside the output, not a sheet (R1)")
        XCTAssertTrue(divider.exists)
        XCTAssertEqual(divider.label, "Editor width")                 // R6
        XCTAssertEqual(divider.value as? String, "400 points, Standard")
        assertControlsInPane()
        let before = assertUndistorted(inside: divider.frame.minX)
        XCTAssertLessThan(before?.frame.width ?? .infinity, full?.frame.width ?? 0, "the output shrank into its pane")

        // Drag 120 pt towards the leading side: the editor widens to about 520 pt (between snaps: stays).
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -120, dy: 0)))
        let widened: String = (divider.value as? String) ?? ""
        XCTAssertNotEqual(widened, "400 points, Standard", "the editor width changed")
        let after = assertUndistorted(inside: divider.frame.minX)
        assertControlsInPane()
        XCTAssertLessThan(after?.frame.width ?? .infinity, (before?.frame.width ?? 0) - 50, "the output is smaller")

        // Drag back near Standard: it snaps to 400 pt and the output returns to its earlier size.
        let back = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        back.press(forDuration: 0.2, thenDragTo: back.withOffset(CGVector(dx: 110, dy: 0)))
        XCTAssertTrue(poll(2) { (self.divider.value as? String) == "400 points, Standard" }, "snapped: \(divider.value ?? "nil")")
        let snapped = assertUndistorted(inside: divider.frame.minX)
        XCTAssertEqual(snapped?.frame.width ?? 0, before?.frame.width ?? -1, accuracy: 1)

        app.navigationBars["Settings"].buttons["Done"].tap()          // R8
        XCTAssertTrue(pane.disappears(within: 3))
        let closed = assertUndistorted(inside: nil)
        XCTAssertEqual(closed?.frame.width ?? 0, closed?.window.width ?? -1, accuracy: 0.5, "full screen again")
    }

    /// Portrait (the window is taller than wide): the output is letterboxed in its pane, undistorted.
    func testPortraitKeepsTheAspect() throws {
        launch()
        guard app.windows.firstMatch.horizontalSizeClass == .regular else {
            throw XCTSkip("compact width: Settings is a sheet (SettingsUITests)")
        }
        XCUIDevice.shared.orientation = .portrait
        openSettings()
        XCTAssertTrue(pane.appears(within: 3))
        let p = assertUndistorted(inside: divider.frame.minX)
        XCTAssertLessThan(p?.window.width ?? 1, p?.window.height ?? 0, "portrait window")
        XCUIDevice.shared.orientation = .landscapeLeft
    }
}
