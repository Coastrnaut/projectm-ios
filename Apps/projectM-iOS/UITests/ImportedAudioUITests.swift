// AUD-001-T19, T22: an imported track on the iOS Simulator. The test writes a tone, the app imports
// it through `-uitestImportAudio <path>` (the same code path as the Files picker's result; the
// system picker itself is not driven here), and the track plays as In-App Playback. Then the
// original is deleted and the app relaunched: the track is still listed and still plays.
// Simulator only (the app reads the test's file from the host); never device evidence.
import XCTest

@MainActor
final class ImportedAudioUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var folder: URL!

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }
    private var track: XCUIElement { app.buttons["importedTrack"].firstMatch }

    /// A 2 s, 440 Hz, 16-bit stereo WAV in a folder of the test runner.
    private func writeTone(named name: String) throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let frames = 88_200
        var bytes: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + frames * 4)) + Array("WAVEfmt ".utf8)
        bytes += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(44_100))
        bytes += le(UInt32(44_100 * 4)) + le(UInt16(4)) + le(UInt16(16))
        bytes += Array("data".utf8) + le(UInt32(frames * 4))
        bytes.reserveCapacity(bytes.count + frames * 4)
        for frame in 0..<frames {
            let sample = Int16(12_000 * sin(2 * Double.pi * 440 * Double(frame) / 44_100))
            bytes += le(sample) + le(sample)
        }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("aud001-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func launch(_ arguments: [String], acknowledgeNotice: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = arguments + Self.noStore
        app.launch()
        if acknowledgeNotice {
            let acknowledge = app.buttons["acknowledgeNotice"]
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
            acknowledge.tap()
        }
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10), "the chooser offers Import Audio…")
    }

    private func playTrackAndExpectInAppPlayback() {
        XCTAssertTrue(track.waitForExistence(timeout: 15), "the imported track is listed under Your Audio")
        XCTAssertEqual(track.label, "UITestTone, 2 seconds")
        track.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10))
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), indicator.label)   // AUD-001-R18
        XCTAssertFalse(app.staticTexts["In-App Playback failed"].exists)
    }

    func testImportPlayRelaunchWithoutOriginalAndPlayAgain() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        let tone = try writeTone(named: "UITestTone.wav")
        launch(["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", tone.path], acknowledgeNotice: true)
        XCTAssertTrue(app.staticTexts["Your Audio"].exists || app.staticTexts["YOUR AUDIO"].exists)
        XCTAssertTrue(app.buttons["In-App Playback"].exists, "AUD-001-R21: the reference-track row is still there")
        playTrackAndExpectInAppPlayback()
        app.buttons["stop"].tap()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10))

        // The original is deleted; the next launch gets no import argument.
        app.terminate()
        try FileManager.default.removeItem(at: folder)
        launch([], acknowledgeNotice: false)
        playTrackAndExpectInAppPlayback()
        #endif
    }

    func testRefusedFileShowsItsReasonAndIsNotListed() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("aud001-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fake = folder.appendingPathComponent("fake.wav")
        try Data(repeating: 7, count: 4096).write(to: fake)
        launch(["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", fake.path], acknowledgeNotice: true)
        let alert = app.alerts["Import Audio"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.staticTexts["“fake.wav”: This audio file can't be read. It may be damaged."].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["noImportedAudio"].waitForExistence(timeout: 5))
        XCTAssertFalse(track.exists)
        try? FileManager.default.removeItem(at: folder)
        #endif
    }
}
