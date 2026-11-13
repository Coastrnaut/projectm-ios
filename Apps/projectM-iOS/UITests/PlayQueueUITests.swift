// AUD-003-T17: the queue on the iOS Simulator (AUD-003-S2). The test writes three tones, the app
// imports them through `-uitestImportAudio <path>|<path>|<path>` (the code path of the Files
// picker's result), and the test reorders the queue (a) from the chooser, then relaunches and
// reads the order again with nothing playing, and (b) from the transport while a track plays,
// then checks that the playing track went on and Next track follows the new order.
// Simulator only (the app reads the test's files from the host); never device evidence.
import XCTest

@MainActor
final class PlayQueueUITests: XCTestCase {
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
    private var title: XCUIElement { app.staticTexts["transportTitle"] }
    private var entries: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "queueEntry") }

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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("aud003-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folder = url
        }
        let url = folder!.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// ToneA, ToneB, ToneC imported in that order: the list (and the unedited queue) is C, B, A.
    private func launchWithThreeTracks(seconds: Int) throws {
        let paths = try [("ToneA.wav", 440.0), ("ToneB.wav", 550.0), ("ToneC.wav", 660.0)].map {
            try writeTone(named: $0.0, seconds: seconds, frequency: $0.1).path
        }
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", paths.joined(separator: "|")]
            + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        let rows = app.buttons.matching(identifier: "importedTrack")
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 20), "the three tracks are listed")
        XCTAssertTrue(rows.element(boundBy: 0).label.hasPrefix("ToneC"))
    }

    /// The queue's titles in order, read from the rows' labels ("ToneB, 4 seconds, 1 of 3").
    private func queueOrder(count: Int = 3, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        XCTAssertTrue(entries.element(boundBy: count - 1).waitForExistence(timeout: 10), "\(count) queue rows", file: file, line: line)
        var titles: [String] = []
        for index in 0..<entries.count {
            let label = entries.element(boundBy: index).label
            guard let name = label.split(separator: ",").first.map(String.init), titles.last != name else { continue }
            titles.append(name)
        }
        return titles
    }

    /// Touch and hold a queue row, then pick a menu item.
    private func menu(row title: String, _ item: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = entries.matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), title, file: file, line: line)
        row.press(forDuration: 1.0)
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), item, file: file, line: line)
        button.tap()
    }

    private func openQueueFromTheChooser() {
        let row = app.buttons["queueRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.label, "Queue, 3 tracks")
        row.tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
    }

    private func closeQueue() {
        app.buttons["queueDone"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Queue"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    // MARK: - (a) reorder, relaunch, same order, nothing plays (AUD-003-S2)

    func testReorderThreeTracksAndTheOrderSurvivesARelaunch() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's files from the host; simulator only")
        #else
        try launchWithThreeTracks(seconds: 4)
        openQueueFromTheChooser()
        XCTAssertEqual(queueOrder(), ["ToneC", "ToneB", "ToneA"])
        XCTAssertEqual(entries.element(boundBy: 0).label, "ToneC, 4 seconds, 1 of 3")
        menu(row: "ToneC", "Move Down")
        XCTAssertEqual(queueOrder(), ["ToneB", "ToneC", "ToneA"])
        menu(row: "ToneA", "Move Up")
        XCTAssertEqual(queueOrder(), ["ToneB", "ToneA", "ToneC"])
        closeQueue()
        XCTAssertTrue(app.buttons["importAudio"].exists, "still in the chooser: an edit plays nothing")

        // Relaunch without resetting the library.
        app.terminate()
        app.launchArguments = Self.noStore
        app.launch()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10), "the chooser, not the visualizer")
        XCTAssertFalse(indicator.exists, "nothing plays after a relaunch (AUD-003-R15)")
        openQueueFromTheChooser()
        XCTAssertEqual(queueOrder(), ["ToneB", "ToneA", "ToneC"])
        XCTAssertFalse(indicator.exists)
        #endif
    }

    // MARK: - (b) reorder while playing (AUD-003-R7)

    private func showFreshControls(file: StaticString = #filePath, line: UInt = #line) {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if playPause.exists { area.tap() }
        area.tap()
        if !playPause.waitForExistence(timeout: 2) { area.tap() }
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "the transport is shown with the controls", file: file, line: line)
    }

    /// The elapsed time shown, in seconds ("0:05" → 5).
    private func elapsed(file: StaticString = #filePath, line: UInt = #line) -> Int {
        let label = app.staticTexts["transportElapsed"]
        if !label.exists { showFreshControls(file: file, line: line) }
        let parts = label.label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, "elapsed time \"\(label.label)\"", file: file, line: line)
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }

    private func expectTitle(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        if !title.exists { showFreshControls(file: file, line: line) }
        let predicate = NSPredicate(format: "label == %@", text)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: title)], timeout: 10)
        XCTAssertEqual(result, .completed, "title \"\(text)\"; the transport shows \"\(title.label)\"", file: file, line: line)
    }

    func testReorderWhilePlayingKeepsTheTrackAndNextFollowsTheNewOrder() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's files from the host; simulator only")
        #else
        try launchWithThreeTracks(seconds: 30)
        app.buttons.matching(identifier: "importedTrack").element(boundBy: 0).tap()    // ToneC; queue C, B, A
        XCTAssertTrue(indicator.waitForExistence(timeout: 10))
        expectTitle("ToneC")
        let deadline = Date().addingTimeInterval(20)
        while elapsed() < 2, Date() < deadline { usleep(250_000) }
        let before = elapsed()
        XCTAssertGreaterThanOrEqual(before, 2, "playback advances")

        showFreshControls()
        let queueButton = app.buttons["transportQueue"]
        XCTAssertTrue(queueButton.exists, "the transport offers the queue for an imported track")
        XCTAssertEqual(queueButton.label, "Queue")
        queueButton.tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
        XCTAssertEqual(queueOrder(), ["ToneC", "ToneB", "ToneA"])
        XCTAssertTrue(entries.element(boundBy: 0).label.hasSuffix("1 of 3, Now Playing"), entries.element(boundBy: 0).label)
        menu(row: "ToneA", "Move Up")
        XCTAssertEqual(queueOrder(), ["ToneC", "ToneA", "ToneB"])
        closeQueue()

        expectTitle("ToneC")
        XCTAssertGreaterThanOrEqual(elapsed(), before, "the playing track went on: no restart, no jump back")
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), indicator.label)
        showFreshControls()
        app.buttons["transportNext"].tap()
        expectTitle("ToneA")                                    // was ToneB before the reorder
        #endif
    }
}
