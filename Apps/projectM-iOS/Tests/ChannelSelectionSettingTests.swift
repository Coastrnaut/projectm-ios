// AUD-009-T06: the analysis channel setting (AUD-009-R5, R6, R8, R10; contracts C4, C5).
import AudioCore
import XCTest
@testable import projectM_iOS

@MainActor
final class ChannelSelectionSettingTests: XCTestCase {
    /// A fresh defaults suite per test (no setUp/tearDown state).
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ChannelSelectionSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToMixAndPersists() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ChannelSelectionSetting(defaults: defaults)
            XCTAssertEqual(setting.mode, .mix)
            XCTAssertEqual(setting.control.mode, .mix)
            XCTAssertNil(defaults.object(forKey: ChannelSelectionSetting.modeKey), "nothing stored until chosen")
            setting.mode = .side
            XCTAssertEqual(setting.control.mode, .side, "the analysis sees the new mode")
            XCTAssertEqual(defaults.string(forKey: ChannelSelectionSetting.modeKey), "side")
            let reloaded = ChannelSelectionSetting(defaults: defaults)
            XCTAssertEqual(reloaded.mode, .side)
            XCTAssertEqual(reloaded.control.mode, .side)
        }
    }

    func testStoredValuesAndUnknownValues() {
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set("left", forKey: ChannelSelectionSetting.modeKey)
            XCTAssertEqual(ChannelSelectionSetting(defaults: defaults).mode, .left)
            XCTAssertEqual(ChannelSelectionSetting(defaults: defaults).control.mode, .left)
            defaults.set("centre", forKey: ChannelSelectionSetting.modeKey)
            XCTAssertEqual(ChannelSelectionSetting(defaults: defaults).mode, .mix, "unknown string")
            defaults.set(3, forKey: ChannelSelectionSetting.modeKey)
            XCTAssertEqual(ChannelSelectionSetting(defaults: defaults).mode, .mix, "not a string")
        }
    }

    func testTitlesAndSpokenNames() {
        let titles: [String] = AnalysisChannelMode.allCases.map { (mode: AnalysisChannelMode) -> String in ChannelSelectionSetting.title(for: mode) }
        let spoken: [String] = AnalysisChannelMode.allCases.map { (mode: AnalysisChannelMode) -> String in ChannelSelectionSetting.spokenName(for: mode) }
        XCTAssertEqual(titles, ["Mix", "Left", "Right", "Mid", "Side"])
        XCTAssertEqual(spoken, ["Stereo mix", "Left", "Right", "Mid", "Side"])
    }

    func testSelectedReaderSharesTheControlAndComposesWithTheTrim() {
        // AUD-009-R5, R10, contract C4: trim(select(tap)), and a change reaches the running reader.
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = ChannelSelectionSetting(defaults: defaults)
            let trim = InputTrimSetting(defaults: defaults)
            XCTAssertNil(setting.selected(nil), "no tap, no reader")
            XCTAssertNil(trim.trimmed(setting.selected(nil)))
            let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096)
            setting.mode = .left
            let reader = trim.trimmed(setting.selected(ring.analysisTap))
            XCTAssertTrue(reader is InputTrimReader, "the trim is outside")
            let leftOnly: [Float] = [0.25, 0, 0.25, 0]
            var out = [Float](repeating: 9, count: 4)
            leftOnly.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: 2) }
            _ = out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                reader!.read(into: b.baseAddress!, maxFrames: 2)
            }
            XCTAssertEqual(out, [0.25, 0.25, 0.25, 0.25], "Left: L in both channels")
            setting.mode = .right
            leftOnly.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in ring.write(b.baseAddress!, frames: 2) }
            _ = out.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                reader!.read(into: b.baseAddress!, maxFrames: 2)
            }
            XCTAssertEqual(out, [0, 0, 0, 0], "Right on a left-only signal: silent, at the next read")
        }
    }
}
