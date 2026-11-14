// AUD-006-T31: the transport on the iOS Simulator, in real time. The test writes two tones of
// different formats (44.1 kHz stereo and 48 kHz mono), the app imports them through
// `-uitestImportAudio <path>|<path>` (the code path of the Files picker's result), and the test
// drives the transport in the visualizer's controls: play, pause, stop playback, the scrubber,
// next and previous track. It also checks that the transport is offered for In-App Playback only.
// Simulator only (the app reads the test's files from the host); never device evidence.
// Shortened 2026-11-13 under owner rule 7: waits poll every 0.1 s (UITestWaits.swift) instead of
// about once a second; testPlayPauseSeekNextPreviousAndStopOnImportedTracks is split in two ((d) and
// (e) moved to testNextPreviousAndStopPlaybackOnImportedTracks). Every assertion is unchanged.
import XCTest

@MainActor
final class TransportUITests: XCTestCase {
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
    private var scrubber: XCUIElement { app.descendants(matching: .any)["transportScrubber"].firstMatch }

    /// A 16-bit PCM WAV tone in a folder of the test runner.
    private func writeTone(named name: String, seconds: Int, sampleRate: Int, channels: Int, frequency: Double) throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let frames = seconds * sampleRate
        let dataBytes = frames * channels * 2
        var header: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(channels)) + le(UInt32(sampleRate))
        header += le(UInt32(sampleRate * channels * 2)) + le(UInt16(channels * 2)) + le(UInt16(16))
        header += Array("data".utf8) + le(UInt32(dataBytes))
        var samples = [Int16](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let sample = Int16(12_000 * sin(2 * Double.pi * frequency * Double(frame) / Double(sampleRate))).littleEndian
            for channel in 0..<channels { samples[frame * channels + channel] = sample }
        }
        var data = Data(header)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        if folder == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("aud006-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folder = url
        }
        let url = folder!.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func launch(_ arguments: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary"] + arguments + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 10))
        acknowledge.tap()
        XCTAssertTrue(app.buttons["importAudio"].appears(within: 10))
    }

    /// The controls hide after 5 s without interaction; a tap on the picture brings them back.
    private func showControls(file: StaticString = #filePath, line: UInt = #line) {
        if playPause.exists { return }
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        if !playPause.appears(within: 1.5) {
            app.otherElements["visualizerTapArea"].firstMatch.tap()      // the first tap hid them
        }
        XCTAssertTrue(playPause.appears(within: 5), "the transport is shown with the controls", file: file, line: line)
    }

    /// Shows the controls with their full 5 s before they hide again (hides them first when they show).
    private func showFreshControls(file: StaticString = #filePath, line: UInt = #line) {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if playPause.exists {
            area.tap()
            _ = playPause.disappears(within: 2)
        }
        area.tap()
        if !playPause.appears(within: 1.5) { area.tap() }
        XCTAssertTrue(playPause.appears(within: 5), "the transport is shown with the controls", file: file, line: line)
        controlsShownAt = Date()
    }

    /// When the test last showed the controls afresh or used one (they hide 5 s later).
    private var controlsShownAt: Date?

    /// The elapsed time shown, in seconds ("1:05" → 65).
    private func elapsed(file: StaticString = #filePath, line: UInt = #line) -> Int {
        // The controls hide 5 s after the last interaction, possibly between showing them and the
        // read (seen 2026-11-13): read only an element that exists now, showing them afresh if needed.
        let label = app.staticTexts["transportElapsed"]
        if (controlsShownAt.map { Date().timeIntervalSince($0) > 3 } ?? true) || !label.exists {
            showFreshControls(file: file, line: line)
        }
        let parts = label.label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, "elapsed time \"\(app.staticTexts["transportElapsed"].label)\"", file: file, line: line)
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }

    private func waitForElapsed(atLeast seconds: Int, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var seen: [String] = []
        while Date() < deadline {
            let value = elapsed(file: file, line: line)
            if value >= seconds { return }
            seen.append("\(value) (\(title.label))")
            usleep(250_000)
        }
        XCTFail("the elapsed time did not reach \(seconds) s; it showed \(seen)", file: file, line: line)
    }

    /// Waits until the elapsed time shown is at most `seconds` (the display follows a jump within
    /// a refresh), and returns it.
    @discardableResult
    private func waitForElapsed(atMost seconds: Int, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var seen: [Int] = []
        while Date() < deadline {
            let value = elapsed(file: file, line: line)
            if value <= seconds { return value }
            seen.append(value)
            usleep(100_000)
        }
        XCTFail("the elapsed time did not go back to \(seconds) s or less; it showed \(seen)", file: file, line: line)
        return seen.last ?? -1
    }

    private func expectState(_ state: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let ok = poll(timeout) { self.indicator.exists && self.indicator.label == "In-App Playback · \(state)" }
        XCTAssertTrue(ok, "state \"\(state)\"; indicator shows \"\(indicator.label)\"", file: file, line: line)
    }

    private func expectTitle(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        showControls(file: file, line: line)
        let ok = poll(10) { self.title.exists && self.title.label == text }
        XCTAssertTrue(ok, "title \"\(text)\"; the transport shows \"\(title.label)\"", file: file, line: line)
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        app.tapFreshControl(id, file: file, line: line)   // the controls could hide between a check and the tap
        controlsShownAt = Date()
    }

    // MARK: - Imported tracks

    /// Imports the two tones, checks the list (newest first) and plays the first row, ToneB.
    private func importTwoTonesAndPlayTheFirst() throws {
        let stereo = try writeTone(named: "ToneA.wav", seconds: 20, sampleRate: 44_100, channels: 2, frequency: 440)
        let mono = try writeTone(named: "ToneB.wav", seconds: 20, sampleRate: 48_000, channels: 1, frequency: 660)
        launch(["-uitestImportAudio", "\(stereo.path)|\(mono.path)"])
        // Newest first: ToneB is listed above ToneA.
        let rows = app.buttons.matching(identifier: "importedTrack")
        let second = rows.element(boundBy: 1)
        XCTAssertTrue(second.appears(within: 20), "both tracks are listed")
        XCTAssertEqual(rows.element(boundBy: 0).label, "ToneB, 20 seconds")
        XCTAssertEqual(second.label, "ToneA, 20 seconds")
        rows.element(boundBy: 0).tap()
        XCTAssertTrue(indicator.appears(within: 10))
    }

    // Owner rule 7 (2026-11-13): the former single test (34 s, about 15 s of it real-time playback)
    // is split in two at (d). Both import the two tones and play ToneB; (a)-(c) stay here, (d) Next
    // and Previous and (e) Stop playback moved to testNextPreviousAndStopPlaybackOnImportedTracks.

    func testPlayPauseSeekNextPreviousAndStopOnImportedTracks() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's files from the host; simulator only")
        #else
        try importTwoTonesAndPlayTheFirst()

        // (a) The transport is part of the controls and playback advances.
        showControls()
        for id in ["transportPrevious", "transportPlayPause", "transportStop", "transportNext"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        XCTAssertEqual(app.buttons["transportPrevious"].label, "Previous track")
        XCTAssertEqual(app.buttons["transportNext"].label, "Next track")
        XCTAssertEqual(app.buttons["transportStop"].label, "Stop playback")
        XCTAssertEqual(playPause.label, "Pause playback")
        XCTAssertTrue(scrubber.exists)
        XCTAssertTrue(app.staticTexts["transportRemaining"].label.hasPrefix("−"))
        expectTitle("ToneB")
        XCTAssertTrue(app.buttons["stop"].exists, "the existing Stop is still there (AUD-006-R23)")
        XCTAssertTrue(app.buttons["pauseResume"].exists)
        expectState("Active audio")
        waitForElapsed(atLeast: 2)

        // (b) Pause playback: Paused, the time holds; Play: it goes on.
        tap("transportPlayPause")
        expectState("Paused")
        showControls()
        XCTAssertEqual(playPause.label, "Play")
        let held = elapsed()
        sleep(3)
        XCTAssertEqual(elapsed(), held, "the position does not move while paused")
        XCTAssertEqual(indicator.label, "In-App Playback · Paused")
        tap("transportPlayPause")
        expectState("Active audio")
        showControls()
        XCTAssertEqual(playPause.label, "Pause playback")
        waitForElapsed(atLeast: held + 2)

        // (c) The scrubber moves the position: a drag to 60%, then a touch at 25%.
        showControls()
        XCTAssertEqual(scrubber.label, "Playback position")
        XCTAssertTrue((scrubber.value as? String ?? "").hasSuffix(" of 20 seconds"), "\(String(describing: scrubber.value))")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        let afterDrag = elapsed()
        XCTAssertGreaterThanOrEqual(afterDrag, 11, "the drag moved playback to about 12 s")
        XCTAssertLessThanOrEqual(afterDrag, 15)
        waitForElapsed(atLeast: afterDrag + 1)
        showControls()
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let afterTouch = elapsed()
        XCTAssertGreaterThanOrEqual(afterTouch, 4, "the touch moved playback back to about 5 s")
        XCTAssertLessThanOrEqual(afterTouch, 8)
        waitForElapsed(atLeast: afterTouch + 1)
        expectState("Active audio")
        #endif
    }

    func testNextPreviousAndStopPlaybackOnImportedTracks() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's files from the host; simulator only")
        #else
        try importTwoTonesAndPlayTheFirst()
        expectTitle("ToneB")
        expectState("Active audio")

        // (d) Next track (another sample rate and channel count), then Previous within 3 s.
        tap("transportNext")
        expectTitle("ToneA")
        waitForElapsed(atMost: 2)                               // the next track starts at its beginning
        XCTAssertEqual(indicator.label.hasPrefix("In-App Playback · "), true)
        waitForElapsed(atLeast: 1)
        expectState("Active audio")
        tap("transportNext")
        expectTitle("ToneB")                                    // after the last track comes the first
        showControls()                                          // just used: no fresh show, to stay within 3 s
        app.buttons["transportPrevious"].tap()
        controlsShownAt = Date()
        expectTitle("ToneA")                                    // within 3 s: the track before, wrapping

        // (e) Stop playback: 0:00, Paused, still in the visualizer; Play starts from the beginning.
        waitForElapsed(atLeast: 2)
        tap("transportStop")
        expectState("Paused")
        XCTAssertEqual(waitForElapsed(atMost: 0), 0)
        XCTAssertEqual(playPause.label, "Play")
        XCTAssertTrue(app.otherElements["visualizer"].exists || app.otherElements["visualizerTapArea"].exists)
        XCTAssertFalse(app.buttons["importAudio"].exists, "Stop playback does not leave the visualizer")
        sleep(2)
        XCTAssertEqual(elapsed(), 0)
        tap("transportPlayPause")
        expectState("Active audio")
        waitForElapsed(atLeast: 1)
        XCTAssertFalse(app.staticTexts["In-App Playback failed"].exists)

        // The existing Stop still returns to the chooser.
        tap("stop")
        XCTAssertTrue(app.buttons["importAudio"].appears(within: 10))
        #endif
    }

    // MARK: - Reference track

    func testReferenceTrackHasTheTransportAndHidesWithTheControls() {
        launch([])
        app.buttons["In-App Playback"].tap()
        XCTAssertTrue(indicator.appears(within: 10))
        expectTitle("Reference track")
        expectState("Active audio")
        waitForElapsed(atLeast: 2)
        tap("transportNext")                                    // the only track: it starts again
        expectTitle("Reference track")
        waitForElapsed(atMost: 2)
        waitForElapsed(atLeast: 4)
        tap("transportPrevious")                                // more than 3 s in: restart
        waitForElapsed(atMost: 2)

        // (h) The transport hides with the controls and returns with them.
        showControls()
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        XCTAssertTrue(playPause.disappears(within: 5), "hidden with the controls")
        XCTAssertFalse(scrubber.exists)
        XCTAssertTrue(indicator.exists, "the source indicator stays")
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        XCTAssertTrue(playPause.appears(within: 5))
    }

    // MARK: - Other sources have no transport (AUD-006-R1)

    func testNoTransportForOtherSources() {
        for (mode, row) in [("systemAppCapture", "System/App Capture"), ("inAppPlayback", "In-App Playback")] {
            // A scripted fake stands in for the mode's source. For In-App Playback this shows that
            // the transport only controls its own source.
            XCUIDevice.shared.orientation = .portrait
            app.launchArguments = ["-uitestResetNotice", "-uitestFake", mode] + Self.noStore
            app.launch()
            app.buttons["acknowledgeNotice"].tap()
            XCTAssertTrue(app.buttons[row].appears(within: 10))
            app.buttons[row].tap()
            XCTAssertTrue(indicator.appears(within: 10))
            XCTAssertTrue(app.buttons["stop"].appears(within: 5), "the controls are visible")
            for id in ["transportPrevious", "transportPlayPause", "transportStop", "transportNext"] {
                XCTAssertFalse(app.buttons[id].exists, "\(mode): \(id)")
            }
            XCTAssertFalse(scrubber.exists, mode)
            XCTAssertFalse(title.exists, mode)
            app.terminate()
        }
    }
}
