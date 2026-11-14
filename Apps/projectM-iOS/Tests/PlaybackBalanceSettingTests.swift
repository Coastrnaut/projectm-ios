// PlaybackBalanceSettingTests.swift — AUD-010-T12: the balance setting (AUD-010-R6 to R9, S3, S4;
// contract C2).
import AudioCore
import CaptureKit
import LibraryBackup
import XCTest
@testable import projectM_iOS

@MainActor
final class PlaybackBalanceSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "PlaybackBalanceSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToCentreAndPersists() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = PlaybackBalanceSetting(defaults: defaults)
            XCTAssertEqual(setting.position, 0)
            XCTAssertNil(defaults.object(forKey: PlaybackBalanceSetting.positionKey), "nothing stored until chosen")
            var pushed: [Double] = []
            setting.onChange = { (value: Double) -> Void in pushed.append(value) }
            setting.position = -0.3
            XCTAssertEqual(defaults.double(forKey: PlaybackBalanceSetting.positionKey), -0.3)
            XCTAssertEqual(pushed, [-0.3], "pushed to playback once")
            XCTAssertEqual(PlaybackBalanceSetting(defaults: defaults).position, -0.3, "relaunch")
        }
    }

    func testInvalidValuesNeverReachPlayback() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = PlaybackBalanceSetting(defaults: defaults)
            var pushed: [Double] = []
            setting.onChange = { (value: Double) -> Void in pushed.append(value) }
            let cases: [(input: Double, expected: Double)] = [(5, 1), (-2, -1), (.nan, 0), (0.025, 0), (0.456, 0.46)]
            for item in cases {
                setting.position = item.input
                XCTAssertEqual(setting.position, item.expected, accuracy: 1e-12, "input \(item.input)")
                XCTAssertEqual(defaults.double(forKey: PlaybackBalanceSetting.positionKey), item.expected, accuracy: 1e-12)
            }
            XCTAssertEqual(pushed.count, cases.count)
            XCTAssertTrue(pushed.allSatisfy { (value: Double) -> Bool in (-1...1).contains(value) })
            defaults.set(9.0, forKey: PlaybackBalanceSetting.positionKey)
            XCTAssertEqual(PlaybackBalanceSetting(defaults: defaults).position, 1, "stored out of range → clamped")
            defaults.set("left", forKey: PlaybackBalanceSetting.positionKey)
            XCTAssertEqual(PlaybackBalanceSetting(defaults: defaults).position, 0, "not a number → centre")
        }
    }

    func testResetCentres() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = PlaybackBalanceSetting(defaults: defaults)
            setting.position = 0.8
            setting.reset()
            XCTAssertEqual(setting.position, 0)
            XCTAssertEqual(defaults.double(forKey: PlaybackBalanceSetting.positionKey), 0)
        }
    }

    func testTexts() {
        XCTAssertEqual(PlaybackBalanceSetting.text(for: 0), "Centered")
        XCTAssertEqual(PlaybackBalanceSetting.text(for: 0.02), "Centered", "detent")
        XCTAssertEqual(PlaybackBalanceSetting.text(for: -0.3), "30% left")
        XCTAssertEqual(PlaybackBalanceSetting.text(for: 1), "100% right")
        XCTAssertEqual(PlaybackBalanceSetting.spokenText(for: 0), "centered")
        XCTAssertEqual(PlaybackBalanceSetting.spokenText(for: -0.3), "30 percent left")
        XCTAssertEqual(PlaybackBalanceSetting.spokenText(for: 0.5), "50 percent right")
    }

    /// S3: only In-App Playback (the one source the app plays aloud).
    func testAvailableForInAppPlaybackOnly() {
        XCTAssertTrue(PlaybackBalanceSetting.isAvailable(for: .inAppPlayback))
        XCTAssertFalse(PlaybackBalanceSetting.isAvailable(for: .microphone))
        XCTAssertFalse(PlaybackBalanceSetting.isAvailable(for: .systemAppCapture))
        XCTAssertFalse(PlaybackBalanceSetting.isAvailable(for: nil))
    }

    /// R9: backed up and erased with Settings (FILE-005), never excluded.
    func testKeyIsInTheBackupPolicy() {
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(PlaybackBalanceSetting.positionKey))
        XCTAssertFalse(LibrarySettingsPolicy.excludedKeys.contains(PlaybackBalanceSetting.positionKey))
    }
}
