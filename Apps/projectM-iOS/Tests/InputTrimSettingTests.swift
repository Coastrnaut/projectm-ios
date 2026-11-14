// AUD-008-T06: the input trim setting (AUD-008-R4, R6, R9; contract C5).
import AudioCore
import XCTest
@testable import projectM_iOS

@MainActor
final class InputTrimSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "InputTrimSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToZeroAndPersists() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = InputTrimSetting(defaults: defaults)
            XCTAssertEqual(setting.decibels, 0)
            XCTAssertEqual(setting.control.decibels, 0)
            XCTAssertNil(defaults.object(forKey: InputTrimSetting.decibelsKey), "nothing stored until chosen")
            setting.decibels = 6
            XCTAssertEqual(setting.control.decibels, 6, "the analysis sees the new target")
            XCTAssertEqual(defaults.double(forKey: InputTrimSetting.decibelsKey), 6)
            let reloaded = InputTrimSetting(defaults: defaults)
            XCTAssertEqual(reloaded.decibels, 6)
            XCTAssertEqual(reloaded.control.decibels, 6)
        }
    }

    func testClampsRoundsAndRejectsNaN() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = InputTrimSetting(defaults: defaults)
            let cases: [(input: Double, expected: Double)] = [(30, 24), (-40, -12), (5.4, 5), (-2.6, -3), (.nan, 0)]
            for item in cases {
                setting.decibels = item.input
                XCTAssertEqual(setting.decibels, item.expected, "input \(item.input)")
                XCTAssertEqual(defaults.double(forKey: InputTrimSetting.decibelsKey), item.expected, "stored = shown")
                XCTAssertEqual(Double(setting.control.decibels), item.expected)
            }
            defaults.set(99.0, forKey: InputTrimSetting.decibelsKey)
            XCTAssertEqual(InputTrimSetting(defaults: defaults).decibels, 24, "a stored value out of range is clamped")
            defaults.set("loud", forKey: InputTrimSetting.decibelsKey)
            XCTAssertEqual(InputTrimSetting(defaults: defaults).decibels, 0, "not a number → 0 dB")
        }
    }

    func testResetStoresZero() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = InputTrimSetting(defaults: defaults)
            setting.decibels = -9
            setting.reset()
            XCTAssertEqual(setting.decibels, 0)
            XCTAssertEqual(setting.control.decibels, 0)
            XCTAssertEqual(InputTrimSetting(defaults: defaults).decibels, 0)
        }
    }

    func testTextIsSignedWholeDecibels() {
        XCTAssertEqual(InputTrimSetting.text(for: 6), "+6 dB")
        XCTAssertEqual(InputTrimSetting.text(for: 0), "0 dB")
        XCTAssertEqual(InputTrimSetting.text(for: -12), "\u{2212}12 dB")
        XCTAssertEqual(InputTrimSetting.text(for: 24), "+24 dB")
    }

    func testTrimmedReaderSharesTheControl() {
        // AUD-008-R11: every analysis consumer gets a reader following the same control.
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = InputTrimSetting(defaults: defaults)
            XCTAssertNil(setting.trimmed(nil), "no tap, no reader")
            let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
            setting.decibels = 6
            let reader = setting.trimmed(ring.analysisTap)
            XCTAssertTrue(reader is InputTrimReader)
            let frames = 3_000
            let samples = [Float](repeating: 0.1, count: 2 * frames)
            var out = [Float](repeating: 0, count: 2 * frames)
            samples.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: 2) }
            _ = out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                reader!.read(into: b.baseAddress!, maxFrames: 2)
            }
            XCTAssertEqual(out[0], 0.1995, accuracy: 1e-3, "+6 dB on the analysis copy")
            setting.decibels = 0   // a change in Settings reaches the running reader
            samples.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: frames) }
            let read = out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                reader!.read(into: b.baseAddress!, maxFrames: frames)
            }
            XCTAssertEqual(read, frames)
            XCTAssertGreaterThan(out[0], 0.19, "ramping down, no step")
            XCTAssertEqual(out[2 * (frames - 1)], 0.1, "settled at 0 dB after the ramp")
        }
    }
}
