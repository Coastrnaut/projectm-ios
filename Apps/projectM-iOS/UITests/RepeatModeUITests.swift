// AUD-004-T15: the repeat modes on the iOS Simulator (AUD-004-S4, S5). The test writes three tones,
// the app imports them through `-uitestImportAudio <path>|<path>|<path>` (the code path of the Files
// picker's result), and the test sets each mode — from the queue screen in the chooser and from the
// transport's Repeat button while a track plays — and relaunches after each, reading the same mode
// back. End-of-track behavior itself is proved frame-exact by CaptureKit's RepeatPipelineTests.
// Simulator only (the app reads the test's files from the host); never device evidence.
import XCTest

@MainActor
final class RepeatModeUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var folder: URL?

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }
    private var playPause: XCUIElement { app.buttons["transportPlayPause"] }
    private var repeatButton: XCUIElement { app.buttons["transportRepeat"] }

    private func row(_ mode: String) -> XCUIElement { app.buttons["repeatMode.\(mode)"] }

    /// A 16-bit stereo 44.1 kHz WAV tone in a folder of the test runner.
    private func writeTone(named name: String, seconds: Int, frequency: Double) throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let frames = seconds * 44_100
        var header: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + frames * 4)) + Array("WAVEfmt ".utf8)
        header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(44_100))
        header += le(UInt32(44_100 * 4)) + le(UInt16(4)) + le(UInt16(16))
        header += Array("data".utf8) + le(UInt32(frames * 4))
        var samples = [Int16](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let sample = Int16(12_000 * sin(2 * Double.pi * frequency * Double(frame) / 44_100)).littleEndian
            samples[frame * 2] = sample
            samples[frame * 2 + 1] = sample
        }
        var data = Data(header)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        if folder == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("aud004-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folder = url
        }
        let url = folder!.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func launchWithThreeTracks() throws {
        let paths = try [("ToneA.wav", 440.0), ("ToneB.wav", 550.0), ("ToneC.wav", 660.0)].map {
            try writeTone(named: $0.0, seconds: 30, frequency: $0.1).path
        }
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", paths.joined(separator: "|")]
            + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "importedTrack").element(boundBy: 2).waitForExistence(timeout: 20),
                      "the three tracks are listed")
    }

    /// Relaunch without resetting the library: the chooser, nothing playing.
    private func relaunch() {
        app.terminate()
        app.launchArguments = Self.noStore
        app.launch()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10), "the chooser, not the visualizer")
    }

    private func openQueueFromTheChooser() {
        let queueRow = app.buttons["queueRow"]
        XCTAssertTrue(queueRow.waitForExistence(timeout: 10))
        queueRow.tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
    }

    private func closeQueue() {
        app.buttons["queueDone"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Queue"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    /// The queue screen marks exactly `mode` as selected.
    private func expectSelected(_ mode: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(row(mode).waitForExistence(timeout: 5), "row \(mode)", file: file, line: line)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: row(mode))
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed, "\(mode) is selected", file: file, line: line)
        for other in ["off", "one", "all"] where other != mode {
            XCTAssertFalse(row(other).isSelected, "\(other) is not selected", file: file, line: line)
        }
    }

    private func showFreshControls(file: StaticString = #filePath, line: UInt = #line) {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if playPause.exists { area.tap() }
        area.tap()
        if !playPause.waitForExistence(timeout: 2) { area.tap() }
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "the transport is shown with the controls", file: file, line: line)
    }

    /// The Repeat button's value, read from freshly shown controls.
    private func repeatValue(file: StaticString = #filePath, line: UInt = #line) -> String {
        showFreshControls(file: file, line: line)
        XCTAssertTrue(repeatButton.exists, "the transport offers Repeat for an imported track", file: file, line: line)
        XCTAssertEqual(repeatButton.label, "Repeat", file: file, line: line)
        return repeatButton.value as? String ?? ""
    }

    func testEachModeIsSetFromTheUIAndSurvivesARelaunch() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's files from the host; simulator only")
        #else
        try launchWithThreeTracks()

        // Off, from the queue screen in the chooser.
        openQueueFromTheChooser()
        expectSelected("all")                                  // the default (AUD-004-R2)
        XCTAssertEqual(row("off").label, "Off")
        XCTAssertEqual(row("one").label, "One Track")
        XCTAssertEqual(row("all").label, "All Tracks")
        row("off").tap()
        expectSelected("off")
        closeQueue()
        relaunch()
        openQueueFromTheChooser()
        expectSelected("off")
        closeQueue()

        // From the transport while a track plays: Off → All Tracks → One Track.
        app.buttons.matching(identifier: "importedTrack").element(boundBy: 0).tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10))
        XCTAssertEqual(repeatValue(), "Off")
        repeatButton.tap()
        XCTAssertEqual(repeatValue(), "All Tracks")
        repeatButton.tap()
        XCTAssertEqual(repeatValue(), "One Track")
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), indicator.label)
        relaunch()
        openQueueFromTheChooser()
        expectSelected("one")

        // All Tracks again, from the queue screen.
        row("all").tap()
        expectSelected("all")
        closeQueue()
        relaunch()
        openQueueFromTheChooser()
        expectSelected("all")
        #endif
    }

    func testTheReferenceTrackHasNoRepeatControl() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary"] + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        let reference = app.buttons["In-App Playback"]
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        reference.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10))
        showFreshControls()
        XCTAssertFalse(repeatButton.exists, "the reference track repeats by itself (AUD-004-R11)")
    }
}
