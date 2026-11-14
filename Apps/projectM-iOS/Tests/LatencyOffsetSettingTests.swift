// AUD-013-T06, T10: the per-source visual delay setting (AUD-013-R1, R8, R9, R11; data model;
// contract C4). Own defaults suite per test; no main-actor state in setUp/tearDown.
import AudioCore
import XCTest
@testable import projectM_iOS

@MainActor
final class LatencyOffsetSettingTests: XCTestCase {
    private func withDefaults(_ body: @MainActor (UserDefaults) -> Void) {
        let suite = "LatencyOffsetSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsAndRelaunchPersistence() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = LatencyOffsetSetting(defaults: defaults)
            for mode in AudioSourceMode.allCases {
                XCTAssertEqual(setting.milliseconds(for: mode), 0, "\(mode) defaults to 0 ms")
                XCTAssertNil(defaults.object(forKey: LatencyOffsetSetting.key(for: mode)), "nothing stored until changed")
            }
            XCTAssertEqual(setting.control.targetFrames, 0)
            setting.setMilliseconds(180, for: .inAppPlayback)
            setting.setMilliseconds(40, for: .systemAppCapture)
            let reloaded = LatencyOffsetSetting(defaults: defaults)   // relaunch
            XCTAssertEqual(reloaded.milliseconds(for: .inAppPlayback), 180)
            XCTAssertEqual(reloaded.milliseconds(for: .systemAppCapture), 40)
            XCTAssertEqual(reloaded.milliseconds(for: .microphone), 0)
            XCTAssertEqual(LatencyOffsetSetting.allKeys.count, 3)
            XCTAssertEqual(Set(LatencyOffsetSetting.allKeys), ["settings.latencyOffset.microphone",
                                                               "settings.latencyOffset.inAppPlayback",
                                                               "settings.latencyOffset.systemAppCapture"])
        }
    }

    func testStoredValuesAreValidated() {
        withDefaults { (defaults: UserDefaults) -> Void in
            defaults.set("slow", forKey: LatencyOffsetSetting.key(for: .microphone))
            defaults.set(Double.nan, forKey: LatencyOffsetSetting.key(for: .inAppPlayback))
            defaults.set(900.0, forKey: LatencyOffsetSetting.key(for: .systemAppCapture))
            let setting = LatencyOffsetSetting(defaults: defaults)
            XCTAssertEqual(setting.milliseconds(for: .microphone), 0, "not a number")
            XCTAssertEqual(setting.milliseconds(for: .inAppPlayback), 0, "NaN")
            XCTAssertEqual(setting.milliseconds(for: .systemAppCapture), 250, "clamped high")
            setting.setMilliseconds(-30, for: .microphone)
            XCTAssertEqual(setting.milliseconds(for: .microphone), 0, "clamped low: visuals can only be delayed")
            setting.setMilliseconds(72.6, for: .microphone)
            XCTAssertEqual(setting.milliseconds(for: .microphone), 73, "whole ms")
            XCTAssertEqual(defaults.double(forKey: LatencyOffsetSetting.key(for: .microphone)), 73)
        }
    }

    /// S3: per-source independence; the active source's value is the control's target.
    func testActiveSourceDrivesTheControlAndSourcesAreIndependent() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = LatencyOffsetSetting(defaults: defaults)
            setting.setMilliseconds(0, for: .microphone)
            setting.setMilliseconds(180, for: .inAppPlayback)
            setting.setMilliseconds(40, for: .systemAppCapture)
            XCTAssertEqual(setting.control.targetFrames, 0, "no source: nothing delayed")
            setting.activeMode = .inAppPlayback
            XCTAssertEqual(setting.control.targetFrames, LatencyOffset.frames(milliseconds: 180))
            setting.activeMode = .systemAppCapture
            XCTAssertEqual(setting.control.targetFrames, LatencyOffset.frames(milliseconds: 40))
            setting.setMilliseconds(100, for: .inAppPlayback)
            XCTAssertEqual(setting.control.targetFrames, LatencyOffset.frames(milliseconds: 40), "another source's edit leaves the target")
            XCTAssertEqual(setting.milliseconds(for: .systemAppCapture), 40, "and its value")
            XCTAssertEqual(setting.milliseconds(for: .microphone), 0)
            setting.setMilliseconds(60, for: .systemAppCapture)
            XCTAssertEqual(setting.control.targetFrames, LatencyOffset.frames(milliseconds: 60), "the active source's edit applies at once")
            setting.activeMode = .microphone
            XCTAssertEqual(setting.control.targetFrames, 0)
            setting.activeMode = nil
            XCTAssertEqual(setting.control.targetFrames, 0)
        }
    }

    func testReadoutTextAndReaders() {
        XCTAssertEqual(LatencyOffsetSetting.text(for: 0), "0 ms")
        XCTAssertEqual(LatencyOffsetSetting.text(for: 180), "180 ms")
        XCTAssertEqual(LatencyOffsetSetting.text(for: 999), "250 ms")
        withDefaults { (defaults: UserDefaults) -> Void in
            let setting = LatencyOffsetSetting(defaults: defaults)
            XCTAssertNil(setting.analysisDelayed(nil))
            let ring = NormalizedPCMRing(analysisTapCapacityFrames: 1_024)
            let analysis = setting.analysisDelayed(ring.analysisTap) as? LatencyDelayReader
            XCTAssertEqual(analysis?.mode, .analysis)
            let renderer = setting.rendererDelayed(ring) as? LatencyDelayReader
            XCTAssertEqual(renderer?.mode, .renderer)
        }
    }

    /// T10 (R9): the estimate uses an injected reading; no audio session.
    func testEstimateUsesTheInjectedReading() {
        withDefaults { (defaults: UserDefaults) -> Void in
            let reading = LatencyOffsetSetting.OutputLatencyReading(outputLatency: 0.160, ioBufferDuration: 0.005)
            let setting = LatencyOffsetSetting(defaults: defaults, outputLatency: { () -> LatencyOffsetSetting.OutputLatencyReading in reading })
            setting.estimate(for: .inAppPlayback)
            XCTAssertEqual(setting.milliseconds(for: .inAppPlayback), 165)
            setting.setMilliseconds(90, for: .microphone)
            setting.estimate(for: .microphone)
            XCTAssertEqual(setting.milliseconds(for: .microphone), 0, "the microphone can't be advanced")
            setting.reset(.inAppPlayback)
            XCTAssertEqual(setting.milliseconds(for: .inAppPlayback), 0)
        }
    }
}
