// PERF-008-T12, T14 (specs/201-perf-008-battery-saver): the roadmap acceptance, "Profile changes effect budgets
// without changing audio source state", on the real objects: a running `CaptureManager` with a counting source, the
// app's `PowerProfileSetting`, the PERF-005 prewarm coordinator, the native spectrum host and the recording limit.
// Thermal state and Low Power are injected; no wall clock is read by any assertion.
import AudioCore
import CaptureKit
import FrameRecording
import Metal
import PresentationLifecycle
import Rendering
import XCTest
@testable import projectM_iOS

@MainActor
final class PowerProfileAppTests: XCTestCase {
    final class CountingSource: AudioSource {
        let mode: AudioSourceMode
        var availability: SourceAvailability = .available
        private(set) var starts = 0
        private(set) var stops = 0
        private(set) var suspends = 0
        init(_ mode: AudioSourceMode) { self.mode = mode }
        func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
            starts += 1
            return AsyncStream.makeStream(of: SourceEvent.self).stream
        }
        func stop() async { stops += 1 }
        func suspend() async { suspends += 1 }
        func resume() async throws {}
    }

    /// Everything about the audio source a profile change must not touch.
    struct AudioSnapshot: Equatable {
        let mode: AudioSourceMode?
        let state: AudioState
        let stopReason: StopReason?
        let pausedByUser: Bool
        let starting: Bool
        let switchingTo: AudioSourceMode?
        let configuration: BackgroundPolicy.Configuration
        let transitions: Int
        let lifecycleEntries: Int
        let starts: Int
        let stops: Int
        let suspends: Int

        @MainActor init(_ manager: CaptureManager, _ source: CountingSource) {
            mode = manager.activeMode
            state = manager.state
            stopReason = manager.stopReason
            pausedByUser = manager.isPausedByUser
            starting = manager.isStarting
            switchingTo = manager.switchingTo
            configuration = manager.backgroundConfiguration
            transitions = manager.transitions.count
            lifecycleEntries = manager.lifecycleLog.count
            starts = source.starts
            stops = source.stops
            suspends = source.suspends
        }
    }

    private var suite = ""

    private func defaults() -> UserDefaults {
        suite = "PowerProfileAppTests." + UUID().uuidString
        return UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        await MainActor.run {
            PowerProfileState.current = .standard
            if !suite.isEmpty { UserDefaults().removePersistentDomain(forName: suite) }
        }
        try await super.tearDown()
    }

    /// The governor's budgets at injected nominal thermal state, Low Power off.
    private func governed(lowPower: Bool = false) -> QualitySettings {
        QualityGovernor.settings(thermal: .nominal, lowPower: lowPower, adaptiveEffects: false,
                                 budget: PowerProfileState.budget(lowPower: lowPower))
    }

    /// Acceptance: Standard → Battery saver → Standard changes the frame-rate cap, render scale and warm-up budget
    /// deterministically, while the running source's state and configuration stay identical.
    func testProfileChangesBudgetsWithoutChangingAudioSourceState() async throws {
        let source = CountingSource(.inAppPlayback)
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false)
        await manager.select(.inAppPlayback)
        let before = AudioSnapshot(manager, source)
        XCTAssertEqual(before.mode, .inAppPlayback)
        XCTAssertEqual(before.starts, 1)

        let setting = PowerProfileSetting(defaults: defaults())
        let loader = PhotoPrewarmLoader(device: nil)
        let prewarm = MediaPrewarmCoordinator(scheduler: PrewarmScheduler(budgetBytes: 1 << 20, loader: loader), loader: loader)
        let applyPrewarm: () -> Void = { () -> Void in
            prewarm.update(thermal: .nominal, lowPower: false, budget: PowerProfileState.budget(lowPower: false))
        }
        applyPrewarm()
        XCTAssertEqual(setting.profile, .standard)
        XCTAssertEqual(governed(), QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0))
        XCTAssertFalse(prewarm.scheduler.lowPower)
        XCTAssertTrue(RendererPresetLoader.allowsWarmUp(lowPower: false))

        setting.profile = .batterySaver
        applyPrewarm()
        XCTAssertEqual(PowerProfileState.current, .batterySaver)
        XCTAssertEqual(governed(), QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75))
        XCTAssertTrue(prewarm.scheduler.lowPower, "media prewarm keeps only the next cue")
        XCTAssertFalse(RendererPresetLoader.allowsWarmUp(lowPower: false), "the SC-104 warm-up is skipped")
        XCTAssertEqual(AudioSnapshot(manager, source), before, "Battery saver leaves the audio source untouched")

        setting.profile = .standard
        applyPrewarm()
        XCTAssertEqual(governed(), QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0))
        XCTAssertFalse(prewarm.scheduler.lowPower)
        XCTAssertEqual(AudioSnapshot(manager, source), before, "returning to Standard leaves it untouched too")
        withExtendedLifetime(prewarm) {}
    }

    /// US2: Follow Low Power Mode is Standard with Low Power off and Battery saver with it on.
    func testFollowLowPowerModeSwitchesWithLowPower() {
        let setting = PowerProfileSetting(defaults: defaults())
        setting.profile = .followLowPowerMode
        XCTAssertEqual(governed(lowPower: false), QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0))
        XCTAssertEqual(governed(lowPower: true), QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75))
        XCTAssertNil(PowerProfileSetting.overlayLine(profile: .followLowPowerMode, lowPower: false))
        XCTAssertEqual(PowerProfileSetting.overlayLine(profile: .followLowPowerMode, lowPower: true),
                       "power follow low power mode 30 fps 0.75x")
        XCTAssertEqual(PowerProfileSetting.overlayLine(profile: .batterySaver, lowPower: false), "power battery saver 30 fps 0.75x")
        XCTAssertNil(PowerProfileSetting.overlayLine(profile: .standard, lowPower: true))
    }

    /// R4: the native spectrum's frame loop takes the profile's cap on its next refresh, without restarting; the
    /// governor still lowers further (critical) and never rises above the cap.
    func testNativeHostFollowsTheProfileWithoutRestarting() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .circular, barCount: .b32)
        host.thermalOverride = .nominal
        host.lowPowerOverride = false
        host.refreshQuality()
        let running: Bool = host.isRunning
        XCTAssertEqual(host.qualitySettings, QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0))

        let setting = PowerProfileSetting(defaults: defaults())
        setting.profile = .batterySaver
        host.refreshQuality()   // what the profile notification triggers
        XCTAssertEqual(host.qualitySettings, QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75))
        host.thermalOverride = .critical
        host.refreshQuality()
        XCTAssertEqual(host.qualitySettings, QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75), "caps do not compound")
        XCTAssertEqual(host.isRunning, running, "the loop is not restarted")

        setting.profile = .standard
        host.refreshQuality()
        XCTAssertEqual(host.qualitySettings, QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75), "critical alone")
        host.thermalOverride = .nominal
        host.refreshQuality()
        XCTAssertEqual(host.qualitySettings, QualitySettings(maxFramesPerSecond: 60, renderScale: 1.0))
    }

    /// R8: the recording render limit names Battery saver only when the profile, not the system, caps.
    func testRecordingRenderLimitReason() {
        XCTAssertNil(RecordingQualitySetting.renderLimit(thermal: .nominal, lowPower: false, budget: .standard))
        XCTAssertEqual(RecordingQualitySetting.renderLimit(thermal: .nominal, lowPower: false, budget: .batterySaver),
                       RecordingRenderLimit(reason: .batterySaver, maximumFramesPerSecond: 30))
        XCTAssertEqual(RecordingQualitySetting.renderLimit(thermal: .nominal, lowPower: true, budget: .batterySaver)?.reason,
                       .lowPowerMode)
        XCTAssertEqual(RecordingQualitySetting.renderLimit(thermal: .serious, lowPower: false, budget: .batterySaver)?.reason,
                       .thermal)
    }

    /// R6: stored under its key, read back by a new setting, unknown → Standard.
    func testProfilePersistsAndUnknownFallsBack() {
        let store = defaults()
        let setting = PowerProfileSetting(defaults: store)
        XCTAssertNil(store.string(forKey: PowerProfileSetting.key), "nothing stored until changed")
        setting.profile = .batterySaver
        XCTAssertEqual(store.string(forKey: PowerProfileSetting.key), "batterySaver")
        XCTAssertEqual(PowerProfileSetting(defaults: store).profile, .batterySaver)
        store.set("turbo", forKey: PowerProfileSetting.key)
        XCTAssertEqual(PowerProfileSetting(defaults: store).profile, .standard)
    }
}
