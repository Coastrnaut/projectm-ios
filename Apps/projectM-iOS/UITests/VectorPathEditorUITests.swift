// VectorPathEditorUITests.swift — SHD-008-T16 on the iOS Simulator (R3, R9; S5): Settings › Particle emitter, spawn
// shape Path, Edit path. Start over, tap a bow-tie: the inline message says the path crosses itself and Close is
// disabled; undo the last point (a triangle): Close closes it. Under 30 s (owner rule 7). Simulator results are UI
// evidence only (Constitution X).
import XCTest

@MainActor
final class VectorPathEditorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openEditor() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-uitestSettingsSection", "particleEmitter", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        let link = app.buttons["particleEmitterLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Particle emitter row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()
        let shape = app.buttons["particleEmitterShape"].firstMatch
        XCTAssertTrue(app.reveal(shape), "the shape picker")
        shape.tap()
        let path = app.buttons["Path"].firstMatch
        XCTAssertTrue(path.appears(within: 5), "Path in the shape menu")
        path.tap()
        let edit = app.buttons["particleEmitterPathEdit"].firstMatch
        XCTAssertTrue(app.reveal(edit), "Edit path")
        edit.tap()
    }

    /// Taps the unit-square point (x, y) on the canvas (VectorPathEditorView.square: 22 pt inset, centred square).
    private func tap(_ canvas: XCUIElement, _ x: Double, _ y: Double) {
        let size: CGSize = canvas.frame.size
        let side: Double = Double(min(size.width, size.height)) - 44
        let ox: Double = (Double(size.width) - side) / 2
        let oy: Double = (Double(size.height) - side) / 2
        let origin = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: ox + x * side, dy: oy + y * side)).tap()
    }

    func testBowTieIsRefusedAndATriangleCloses() {
        openEditor()
        let message = app.staticTexts["vectorPathMessage"].firstMatch
        XCTAssertTrue(message.appears(within: 5), "the editor")
        XCTAssertEqual(message.label, "Path closed, 4 points.", "the default diamond")
        app.buttons["vectorPathStartOver"].firstMatch.tap()
        let canvas = app.descendants(matching: .any)["vectorPathCanvas"].firstMatch
        for (x, y) in [(0.2, 0.2), (0.8, 0.8), (0.8, 0.2), (0.2, 0.8)] { tap(canvas, x, y) }
        XCTAssertTrue(app.descendants(matching: .any)["vectorPathPoint.4"].appears(within: 3), "four points placed")
        XCTAssertTrue(poll(3) { message.label.contains("crosses itself") }, "bow-tie message: \(message.label)")
        let close = app.buttons["vectorPathClose"].firstMatch
        XCTAssertFalse(close.isEnabled, "a bow-tie cannot be closed")
        app.buttons["vectorPathUndoPoint"].firstMatch.tap()
        XCTAssertTrue(poll(3) { close.isEnabled }, "a triangle can be closed")
        close.tap()
        XCTAssertTrue(poll(3) { message.label == "Path closed, 3 points." }, "closed: \(message.label)")
        app.navigationBars.buttons.firstMatch.tap()
        let edit = app.buttons["particleEmitterPathEdit"].firstMatch
        XCTAssertTrue(edit.appears(within: 5))
        XCTAssertTrue(edit.label.contains("3 points"), "the emitter keeps the closed path: \(edit.label)")
    }
}
