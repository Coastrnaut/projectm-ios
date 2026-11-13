// AUD-005-T14: Shuffle on the iOS Simulator (AUD-005-R11, R12, S5). The test writes three short tones,
// the app imports them through `-uitestImportAudio <path>|<path>|<path>`, and the test turns Shuffle on
// from the queue screen, relaunches, reads it back, turns it off from the transport while a track
// plays, and relaunches again. The shuffled order and the history are proved by CaptureKit's
// ShuffleQueueTests and ShuffleTransportTests. Simulator only; never device evidence.
// Short by owner rule 7: 5 s tones, polling waits (`UITestWaits`).
import XCTest

@MainActor
final class ShuffleUITests: XCTestCase {
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
    private var shuffleButton: XCUIElement { app.buttons["transportShuffle"] }
    private var shuffleToggle: XCUIElement { app.switches["shuffleToggle"] }

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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("aud005-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folder = url
        }
        let url = folder!.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func launchWithThreeTracks() throws {
        let paths = try [("ToneA.wav", 440.0), ("ToneB.wav", 550.0), ("ToneC.wav", 660.0)].map {
            try writeTone(named: $0.0, seconds: 5, frequency: $0.1).path
        }
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", paths.joined(separator: "|")]
            + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 10))
        acknowledge.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "importedTrack").element(boundBy: 2).appears(within: 20),
                      "the three tracks are listed")
    }

    /// Relaunch without resetting the library: the chooser, nothing playing.
    private func relaunch() {
        app.terminate()
        app.launchArguments = Self.noStore
        app.launch()
        XCTAssertTrue(app.buttons["importAudio"].appears(within: 10), "the chooser, not the visualizer")
    }

    private func openQueueFromTheChooser() {
        let queueRow = app.buttons["queueRow"]
        XCTAssertTrue(queueRow.appears(within: 10))
        queueRow.tap()
        XCTAssertTrue(app.navigationBars["Queue"].appears(within: 5))
        XCTAssertTrue(shuffleToggle.appears(within: 5), "the queue screen offers Shuffle")
    }

    private func closeQueue() {
        app.buttons["queueDone"].tap()
        XCTAssertTrue(app.navigationBars["Queue"].disappears(within: 5))
    }

    /// The toggle's value as XCUITest reports a switch: "1" on, "0" off.
    private func toggleValue() -> String { shuffleToggle.value as? String ?? "" }

    /// Taps the switch itself (a tap on the row's label does not toggle inside a List). The section
    /// follows "Up Next", so it can sit under the translucent bottom toolbar, which takes the tap even
    /// though XCUITest calls the switch hittable: scroll to the end of the list first.
    private func flipToggle() {
        app.collectionViews.firstMatch.swipeUp()
        let inner = shuffleToggle.switches.firstMatch
        if inner.exists { inner.tap() } else { shuffleToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
    }

    private func showFreshControls(file: StaticString = #filePath, line: UInt = #line) {
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if playPause.exists { area.tap() }
        area.tap()
        if !playPause.appears(within: 2) { area.tap() }
        XCTAssertTrue(playPause.appears(within: 5), "the transport is shown with the controls", file: file, line: line)
    }

    func testShuffleIsSetFromBothPlacesAndSurvivesARelaunch() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's files from the host; simulator only")
        #else
        try launchWithThreeTracks()

        // On, from the queue screen in the chooser.
        openQueueFromTheChooser()
        XCTAssertEqual(toggleValue(), "0", "Shuffle is off by default (AUD-005-R1)")
        flipToggle()
        XCTAssertTrue(poll(5) { self.toggleValue() == "1" }, "Shuffle is on")
        closeQueue()
        relaunch()
        openQueueFromTheChooser()
        XCTAssertEqual(toggleValue(), "1", "Shuffle survives a relaunch")
        closeQueue()

        // Off, from the transport while a track plays.
        app.buttons.matching(identifier: "importedTrack").element(boundBy: 0).tap()
        XCTAssertTrue(indicator.appears(within: 10))
        showFreshControls()
        XCTAssertTrue(shuffleButton.exists, "the transport offers Shuffle for an imported track")
        XCTAssertEqual(shuffleButton.label, "Shuffle")
        XCTAssertEqual(shuffleButton.value as? String, "On")
        shuffleButton.tap()
        showFreshControls()
        XCTAssertTrue(poll(5) { (self.shuffleButton.value as? String) == "Off" }, "Shuffle is off")
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), indicator.label)
        relaunch()
        openQueueFromTheChooser()
        XCTAssertEqual(toggleValue(), "0", "Off survives a relaunch")
        #endif
    }

    func testTheReferenceTrackHasNoShuffleControl() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(indicator.appears(within: 15))
        showFreshControls()
        XCTAssertFalse(shuffleButton.exists, "Shuffle applies to the queue of imported audio only (AUD-005-R11)")
    }
}
