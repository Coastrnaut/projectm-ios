// AUD-014-T22: the roadmap acceptance, synthetic half, on the iOS Simulator in real time:
// "Synthetic interruption ... restore correct transport state."
//
// The test writes a tone, the app imports it (`-uitestImportAudio`, the Files picker's code path)
// and plays it as In-App Playback with the real audio engine and session. The session-event panel
// (`-uitestSessionEvents`, DEBUG only) posts the notifications iOS posts for an interruption and a
// lost output route; the test reads the status line and the transport before, during and after.
// Simulator only (the app reads the test's file from the host), and never device evidence: a
// synthetic notification does not take the audio away. The real phone call is AUD-014-T29.
import XCTest

@MainActor
final class InterruptionUITests: XCTestCase {
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
    private var scrubber: XCUIElement { app.descendants(matching: .any)["transportScrubber"].firstMatch }

    private static let interruptedDetail = "Playback is on hold at its position. It continues when iOS allows it, or press Play."
    private static let outputDetail = "The audio output was disconnected. Press Play to continue."

    /// A 60 s 16-bit PCM WAV tone in a folder of the test runner.
    private func writeTone() throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let sampleRate = 44_100
        let frames = 60 * sampleRate
        let dataBytes = frames * 4
        var header: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(sampleRate))
        header += le(UInt32(sampleRate * 4)) + le(UInt16(4)) + le(UInt16(16))
        header += Array("data".utf8) + le(UInt32(dataBytes))
        var samples = [Int16](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let sample = Int16(12_000 * sin(2 * Double.pi * 440 * Double(frame) / Double(sampleRate))).littleEndian
            samples[frame * 2] = sample
            samples[frame * 2 + 1] = sample
        }
        var data = Data(header)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aud014-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        folder = directory
        let url = directory.appendingPathComponent("Tone.wav")
        try data.write(to: url)
        return url
    }

    /// Imports the tone, plays it and waits until it is verified and 2 s in.
    private func startPlaying() throws {
        let tone = try writeTone()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", tone.path,
                               "-uitestSessionEvents"] + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        let row = app.buttons.matching(identifier: "importedTrack").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the imported track is listed")
        row.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10))
        expectState("Active audio")
        showControls()
        XCTAssertEqual(playPause.label, "Pause playback")
        waitForElapsed(atLeast: 2)
    }

    private func showControls(file: StaticString = #filePath, line: UInt = #line) {
        if playPause.exists { return }
        app.otherElements["visualizerTapArea"].firstMatch.tap()
        if !playPause.waitForExistence(timeout: 3) {
            app.otherElements["visualizerTapArea"].firstMatch.tap()      // the first tap hid them
        }
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "the transport is shown with the controls", file: file, line: line)
    }

    /// Shows the controls with their full 5 s before they hide again: hides them first when they
    /// are showing, so that a touch on a control right afterwards cannot race the hide timer.
    private func showFreshControls(file: StaticString = #filePath, line: UInt = #line) {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if playPause.exists { area.tap() }
        area.tap()
        if !playPause.waitForExistence(timeout: 2) { area.tap() }
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "the transport is shown with the controls", file: file, line: line)
    }

    /// The elapsed time shown, in seconds ("1:05" → 65).
    private func elapsed(file: StaticString = #filePath, line: UInt = #line) -> Int {
        showControls(file: file, line: line)
        let parts = app.staticTexts["transportElapsed"].label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, "elapsed time \"\(app.staticTexts["transportElapsed"].label)\"", file: file, line: line)
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }

    private func waitForElapsed(atLeast seconds: Int, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var seen: [Int] = []
        while Date() < deadline {
            let value = elapsed(file: file, line: line)
            if value >= seconds { return }
            seen.append(value)
            usleep(250_000)
        }
        XCTFail("the elapsed time did not reach \(seconds) s; it showed \(seen)", file: file, line: line)
    }

    private func expectState(_ state: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", "In-App Playback · \(state)")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: indicator)], timeout: timeout)
        XCTAssertEqual(result, .completed, "state \"\(state)\"; indicator shows \"\(indicator.label)\"", file: file, line: line)
    }

    /// An element whose label contains `text` (the banner may present its lines as one element).
    private func text(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func post(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id, file: file, line: line)
        button.tap()
    }

    /// The position shown does not move for 3 s, and the button offers Play.
    private func assertOnHold(file: StaticString = #filePath, line: UInt = #line) -> Int {
        showControls(file: file, line: line)
        XCTAssertEqual(playPause.label, "Play", "the transport shows paused", file: file, line: line)
        let held = elapsed(file: file, line: line)
        sleep(3)
        XCTAssertEqual(elapsed(file: file, line: line), held, "the position does not move while on hold", file: file, line: line)
        return held
    }

    // MARK: - Tests

    func testSyntheticInterruptionHoldsAndResumesAnImportedTrack() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        try startPlaying()
        let before = elapsed()

        // During: Interrupted, with the explanation; the transport is paused where it was.
        post("session:interruptBegan")
        expectState("Interrupted")
        XCTAssertTrue(text(containing: Self.interruptedDetail).waitForExistence(timeout: 5), "the explanation is shown")
        XCTAssertTrue(app.buttons["Restart"].exists, "FR-051: the one-tap restart is still offered")
        let held = assertOnHold()
        XCTAssertGreaterThanOrEqual(held, before, "not behind the position before the interruption")
        XCTAssertLessThanOrEqual(held, before + 2, "held where the interruption began")

        // After, iOS indicates a resume: playing again from the held position.
        post("session:interruptEndedResume")
        expectState("Active audio")
        showControls()
        XCTAssertEqual(playPause.label, "Pause playback")
        XCTAssertFalse(text(containing: Self.interruptedDetail).exists, "the explanation is gone")
        let resumed = elapsed()
        XCTAssertGreaterThanOrEqual(resumed, held)
        XCTAssertLessThanOrEqual(resumed, held + 4, "it continued from the held position, not from elsewhere")
        waitForElapsed(atLeast: held + 3)
        #endif
    }

    func testNoResumeAfterASeekDuringTheInterruptionOrWithoutAResumeIndication() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        try startPlaying()

        // The user moves the scrubber during the interruption: the resume indication is not followed.
        post("session:interruptBegan")
        expectState("Interrupted")
        showFreshControls()
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let sought = elapsed()
        XCTAssertGreaterThanOrEqual(sought, 26, "the touch moved the position to about 30 s")
        XCTAssertLessThanOrEqual(sought, 34)
        post("session:interruptEndedResume")
        XCTAssertEqual(assertOnHold(), sought, "still on hold at the position the user chose")
        XCTAssertEqual(indicator.label, "In-App Playback · Interrupted")

        // Play continues from there.
        showFreshControls()
        playPause.tap()
        expectState("Active audio")
        waitForElapsed(atLeast: sought + 2)

        // An interruption that ends without a resume indication stays on hold; Play continues.
        post("session:interruptBegan")
        expectState("Interrupted")
        post("session:interruptEnded")
        let held = assertOnHold()
        XCTAssertEqual(indicator.label, "In-App Playback · Interrupted")
        showFreshControls()
        playPause.tap()
        expectState("Active audio")
        waitForElapsed(atLeast: held + 2)
        #endif
    }

    func testALostOutputPausesWithItsExplanationAndPlayContinues() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        try startPlaying()
        post("session:routeLost")
        expectState("Paused")
        XCTAssertTrue(text(containing: "Paused — audio route changed").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: Self.outputDetail).exists, "the explanation is shown")
        let held = assertOnHold()

        // An interruption on top of it, with a resume indication, starts nothing.
        post("session:interruptBegan")
        post("session:interruptEndedResume")
        XCTAssertEqual(assertOnHold(), held)
        XCTAssertEqual(indicator.label, "In-App Playback · Paused")

        showFreshControls()
        playPause.tap()
        expectState("Active audio")
        XCTAssertFalse(text(containing: Self.outputDetail).exists)
        waitForElapsed(atLeast: held + 2)
        #endif
    }
}
