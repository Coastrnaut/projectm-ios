// AUD-011-T05: the noise gate setting (AUD-011-R3, R7, R8, R9; contracts C5, C6).
import AudioCore
import XCTest
@testable import projectM_iOS

@MainActor
final class NoiseGateSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "NoiseGateSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsAndPersistence() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = NoiseGateSetting(defaults: defaults)
            XCTAssertFalse(setting.isEnabled, "off by default")
            XCTAssertEqual(setting.thresholdDecibels, -50)
            XCTAssertFalse(setting.control.isEnabled)
            XCTAssertEqual(setting.control.openDecibels, -50)
            XCTAssertNil(defaults.object(forKey: NoiseGateSetting.enabledKey), "nothing stored until changed")
            setting.isEnabled = true
            setting.thresholdDecibels = -40
            XCTAssertTrue(setting.control.isEnabled, "the analysis sees the change")
            XCTAssertEqual(setting.control.openDecibels, -40)
            // Relaunch: a new store on the same defaults.
            let reloaded = NoiseGateSetting(defaults: defaults)
            XCTAssertTrue(reloaded.isEnabled)
            XCTAssertEqual(reloaded.thresholdDecibels, -40)
            XCTAssertTrue(reloaded.control.isEnabled)
            XCTAssertEqual(reloaded.control.openDecibels, -40)
        }
    }

    func testStoredValuesAreValidated() {
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set("yes", forKey: NoiseGateSetting.enabledKey)
            defaults.set("loud", forKey: NoiseGateSetting.thresholdKey)
            let odd = NoiseGateSetting(defaults: defaults)
            XCTAssertFalse(odd.isEnabled, "not a Bool")
            XCTAssertEqual(odd.thresholdDecibels, -50, "not a number")
            defaults.set(Double.nan, forKey: NoiseGateSetting.thresholdKey)
            XCTAssertEqual(NoiseGateSetting(defaults: defaults).thresholdDecibels, -50, "NaN")
            defaults.set(-120.0, forKey: NoiseGateSetting.thresholdKey)
            XCTAssertEqual(NoiseGateSetting(defaults: defaults).thresholdDecibels, -80, "clamped low")
            defaults.set(3.0, forKey: NoiseGateSetting.thresholdKey)
            XCTAssertEqual(NoiseGateSetting(defaults: defaults).thresholdDecibels, -20, "clamped high")
            let setting = NoiseGateSetting(defaults: defaults)
            setting.thresholdDecibels = -44.6
            XCTAssertEqual(setting.thresholdDecibels, -45, "whole dB")
            XCTAssertEqual(defaults.double(forKey: NoiseGateSetting.thresholdKey), -45)
        }
    }

    func testReadoutText() {
        XCTAssertEqual(NoiseGateSetting.text(for: -50), "\u{2212}50 dBFS")
        XCTAssertEqual(NoiseGateSetting.text(for: -20), "\u{2212}20 dBFS")
        XCTAssertEqual(NoiseGateSetting.text(for: -80.4), "\u{2212}80 dBFS")
    }

    func testGatedReaderFollowsTheMicrophoneFlag() {
        // AUD-011-R3, contract C5: the gate acts only while the source is the microphone.
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = NoiseGateSetting(defaults: defaults)
            XCTAssertNil(setting.gated(nil), "no tap, no reader")
            setting.isEnabled = true
            let quiet: [Float] = (0..<1_024).map { (i: Int) -> Float in
                let phase: Float = Float(i) * 0.1
                return 0.000_3 * sinf(phase)   // about −70 dBFS
            }
            @MainActor func readThrough() -> [Float] {
                let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
                quiet.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: 512) }
                guard let reader = setting.gated(ring.analysisTap) else { return [] }
                var out = [Float](repeating: 1, count: 1_024)
                let frames = out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                    reader.read(into: b.baseAddress!, maxFrames: 512)
                }
                XCTAssertEqual(frames, 512)
                return out
            }
            setting.control.isMicrophoneSource = false
            XCTAssertEqual(readThrough().map(\.bitPattern), quiet.map(\.bitPattern), "playback or capture: pass-through")
            setting.control.isMicrophoneSource = true
            XCTAssertTrue(readThrough().allSatisfy { (v: Float) -> Bool in v == 0 }, "microphone: gated")
        }
    }
}
