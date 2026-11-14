// AUD-015-T11: the background policy on the iOS Simulator (AUD-015-S4). A short tone plays as
// In-App Playback (the Files import path, `-uitestImportAudio`); the test presses Home, brings the
// app back and checks that the status returns to "Active audio" (FR-050) and that the return notice
// says playback paused while the app was away (AUD-015-R7). Simulator only, never device evidence;
// the device check per source is AUD-015-T13.
import XCTest

@MainActor
final class BackgroundPolicyUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var folder: URL?

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    /// A 20 s 16-bit PCM WAV tone at 440 Hz in a folder of the test runner.
    private func writeTone() throws -> URL {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] { withUnsafeBytes(of: value.littleEndian) { Array($0) } }
        let sampleRate: Int = 44_100
        let frames: Int = 20 * sampleRate
        let dataBytes: Int = frames * 4
        var header: [UInt8] = Array("RIFF".utf8) + le(UInt32(36 + dataBytes)) + Array("WAVEfmt ".utf8)
        header += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(sampleRate))
        header += le(UInt32(sampleRate * 4)) + le(UInt16(4)) + le(UInt16(16))
        header += Array("data".utf8) + le(UInt32(dataBytes))
        var samples = [Int16](repeating: 0, count: frames * 2)
        let step: Double = 2 * Double.pi * 440 / Double(sampleRate)
        for frame in 0..<frames {
            let phase: Double = step * Double(frame)
            let value: Int16 = Int16(12_000 * sin(phase)).littleEndian
            samples[frame * 2] = value
            samples[frame * 2 + 1] = value
        }
        var data = Data(header)
        samples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in data.append(contentsOf: raw) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aud015-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        folder = directory
        let url = directory.appendingPathComponent("Tone.wav")
        try data.write(to: url)
        return url
    }

    func testHomeAndReturnPausesPlaybackResumesItAndSaysSo() throws {
        let tone = try writeTone()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestResetAudioLibrary", "-uitestImportAudio", tone.path]
            + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 10))
        acknowledge.tap()
        let row = app.buttons.matching(identifier: "importedTrack").firstMatch
        XCTAssertTrue(row.appears(within: 20), "the imported track is listed")
        row.tap()

        let indicator = app.staticTexts["sourceIndicator"]
        let active = "In-App Playback · Active audio"
        XCTAssertTrue(poll(15) { indicator.exists && indicator.label == active }, "playing: \(indicator.label)")
        XCTAssertFalse(app.staticTexts["backgroundNoticeText"].exists, "no notice before leaving")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(poll(10) { self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended },
                      "the app left the foreground")
        app.activate()
        XCTAssertTrue(poll(10) { self.app.state == .runningForeground })

        let notice = app.staticTexts["backgroundNoticeText"]
        XCTAssertTrue(notice.appears(within: 5), "the return notice is shown")
        XCTAssertEqual(notice.label, "Playback paused while projectM-iOS was in the background.")
        XCTAssertTrue(poll(15) { indicator.exists && indicator.label == active },
                      "playback resumed on return (FR-050): \(indicator.label)")

        app.buttons["backgroundNoticeDismiss"].tap()
        XCTAssertTrue(notice.disappears(within: 3), "Dismiss clears it")
    }
}
