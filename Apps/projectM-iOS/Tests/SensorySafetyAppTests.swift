// SensorySafetyAppTests.swift — ACC-012-T13, T15, T16: the acceptance "applying the profile clamps affected
// parameters before render", checked on the renderer inputs (ACC-012-R3 to R8, R11; S1, S3, S4).
// * Table: each profile × glow intensity, bound glow, flash envelope (native frame context, projectM's
//   ANGLE pass, the compositor's guard) through the coordinator's own `applySafety`.
// * Precedence: Reduce flashing (chosen, or following Reduce Motion) raises Standard; the stricter wins; a
//   profile stricter than Standard turns on ACC-002's flagging without writing `settings.reduceFlashing`.
// * Storage: relaunch, clamping, the backup round trip, the UI-test reset list, and R11 (not a parameter).
// Needs a Metal device for the hosts (the simulator renders with the host GPU); skips without one.
import ANGLERendering
import Compositor
import FlashSafety
import LibraryBackup
import Metal
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class SensorySafetyAppTests: XCTestCase {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite: String = "ACC012." + name
        let store: UserDefaults = UserDefaults(suiteName: suite) ?? .standard
        store.removePersistentDomain(forName: suite)
        return store
    }

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func clamp(_ preset: SensorySafetyPreset, reduceFlashing: Bool = false) -> SafetyClamp {
        SafetyClamp(profile: SensorySafetyProfile(preset: preset), reduceFlashingSetting: reduceFlashing)
    }

    // MARK: Acceptance table (ACC-012-S1)

    private struct Row {
        let preset: SensorySafetyPreset
        let glow: Float          // manual 0.8
        let bound: Float         // manual 0.5, the bound band at 1.0
        let budget: Int
        let rise: Double?
    }

    func testApplyingEachProfileClampsEveryRendererInput() throws {
        let device = try device()
        let rows: [Row] = [
            Row(preset: .standard, glow: 0.8, bound: 1.0, budget: 6, rise: nil),
            Row(preset: .reduced, glow: 0.5, bound: 0.5, budget: 4, rise: 0.25),
            Row(preset: .strict, glow: 0.25, bound: 0.25, budget: 2, rise: 0.10),
        ]
        let angle: ANGLERenderer? = try? ANGLERenderer.make()
        let compositor = try Compositor(device: device, texturePool: SharedTexturePool.pool(for: device))
        let manual = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                                 glow: BloomParameters(enabled: true, intensity: 0.8))
        let bound = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                                glow: BloomParameters(enabled: true, intensity: 0.5))
        try bound.bind(AudioFeatureBinding(source: .band(0), target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        let loud: [Float] = [1, 1, 1]
        var time: UInt64 = 1_000_000
        for row in rows {
            let clamp: SafetyClamp = clamp(row.preset)
            AppCoordinator.applySafety(clamp, renderer: angle, native: manual, compositors: [compositor])
            AppCoordinator.applySafety(clamp, renderer: nil, native: bound, compositors: [])
            for _ in 0..<3 {
                time += 16_666_667
                loud.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                    bound.applyModulation(bands: b, timeNanoseconds: time)
                }
            }
            let name: String = row.preset.rawValue
            XCTAssertEqual(manual.bloomParameters?.intensity ?? -1, row.glow, accuracy: 1e-6, "\(name): the bloom's input")
            XCTAssertEqual(manual.glow.intensity, 0.8, "\(name): the manual setting is unchanged")
            XCTAssertEqual(bound.bloomParameters?.intensity ?? -1, row.bound, accuracy: 1e-6, "\(name): a binding cannot pass the cap")
            let white = LinearColor(red: 1, green: 1, blue: 1, alpha: 1)
            let model: Double = try XCTUnwrap(bound.downstreamLuminance).outputLuminance(ofFlatColor: white)
            XCTAssertEqual(model, BloomLuminanceModel(parameters: bound.effectiveGlow).outputLuminance(ofFlatColor: white),
                           "\(name): the flash limiter sees the clamped glow")
            let context: VisualFrameContext = manual.frameContext(timeNanoseconds: time, frameDuration: 1.0 / 60)
            XCTAssertEqual(context.flashConfiguration.transitionBudget, row.budget, "\(name): native envelope")
            XCTAssertEqual(context.flashConfiguration.riseRatePerSecond, row.rise, "\(name): native rise")
            let composite: FlashEnvelopeConfiguration = compositor.flashLimits ?? .forReduceFlashing(clamp.reducesFlashing)
            XCTAssertEqual(composite, clamp.flashConfiguration, "\(name): the compositor guard's envelope")
            if let angle {
                XCTAssertEqual(angle.flashConfiguration.transitionBudget, row.budget, "\(name): projectM's envelope")
                XCTAssertEqual(angle.flashConfiguration.riseRatePerSecond, row.rise, "\(name): projectM's rise")
                XCTAssertEqual(angle.reduceFlashing, row.preset != .standard)
            }
        }
        XCTAssertNotNil(angle, "ANGLE renders in the simulator; projectM's row must be checked")
    }

    func testStandardLeavesEveryRendererOnTodaysPath() throws {
        let device = try device()
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.8))
        let before: BloomParameters? = host.bloomParameters
        AppCoordinator.applySafety(.standard, renderer: nil, native: host, compositors: [])
        XCTAssertEqual(host.bloomParameters, before)
        XCTAssertNil(host.frameContext(timeNanoseconds: 1, frameDuration: 0.016).flashLimits, "no override: today's code path")
        XCTAssertEqual(host.effectiveGlow, host.glow)
    }

    // MARK: Precedence (ACC-012-R7, S3)

    func testReduceFlashingRaisesStandardAndTheStricterWins() {
        let store: UserDefaults = defaults()
        let settings = AppSettings(defaults: store, systemReduceMotion: true)   // Reduce flashing follows Reduce Motion
        XCTAssertTrue(settings.reduceFlashing)
        XCTAssertEqual(settings.safetyClamp.flashConfiguration, .reduceFlashing, "Standard raised to Reduced's envelope")
        XCTAssertEqual(settings.safetyClamp.limits.intensityLimit, 1, "Reduce Motion alone caps nothing (ACC-001-R5)")
        settings.sensorySafety.preset = .strict
        XCTAssertEqual(settings.safetyClamp.limits, .strict)
        settings.systemReduceMotion = false
        settings.reduceFlashing = true
        settings.sensorySafety.preset = .standard
        XCTAssertEqual(settings.safetyClamp.flashConfiguration.transitionBudget, 4, "the chosen toggle raises it too")
        settings.reduceFlashing = false
        XCTAssertFalse(settings.effectiveReduceFlashing)
        XCTAssertTrue(settings.safetyClamp.isIdentity)
    }

    func testAStricterProfileFlagsMayFlashPresetsWithoutWritingTheToggle() {
        let store: UserDefaults = defaults()
        let settings = AppSettings(defaults: store, systemReduceMotion: false)
        settings.reduceFlashing = false
        settings.sensorySafety.preset = .reduced
        XCTAssertTrue(settings.effectiveReduceFlashing, "ACC-002's policy and the bar slew follow")
        XCTAssertFalse(settings.reduceFlashing, "the user's stored choice is untouched")
        XCTAssertEqual(store.object(forKey: AppSettings.reduceFlashingKey) as? Bool, false)
    }

    // MARK: Storage (ACC-012-R8, S4)

    func testProfileAndCustomValuesSurviveARelaunch() {
        let store: UserDefaults = defaults()
        let first = AppSettings(defaults: store, systemReduceMotion: false)
        first.sensorySafety.preset = .strict
        first.sensorySafety.preset = .custom   // seeded from Strict (clarify Q3)
        XCTAssertEqual(first.sensorySafety.custom, .strict)
        first.sensorySafety.flashesPerSecond = 2
        first.sensorySafety.riseLimitSliderValue = 0.2
        first.sensorySafety.intensityLimit = 0.6
        let relaunched = AppSettings(defaults: store, systemReduceMotion: false)
        XCTAssertEqual(relaunched.sensorySafety.preset, .custom)
        XCTAssertEqual(relaunched.sensorySafety.custom,
                       SensorySafetyLimits(flashesPerSecond: 2, riseLimitPerSecond: 0.2, intensityLimit: 0.6))
        relaunched.sensorySafety.riseLimitSliderValue = 0
        XCTAssertNil(AppSettings(defaults: store, systemReduceMotion: false).sensorySafety.custom.riseLimitPerSecond, "0 = none")
    }

    func testMalformedStoredValuesReadSafely() {
        let store: UserDefaults = defaults()
        store.set("loudest", forKey: SensorySafetySetting.profileKey)
        store.set(9, forKey: SensorySafetySetting.flashesPerSecondKey)
        store.set(-4.0, forKey: SensorySafetySetting.intensityLimitKey)
        let settings = AppSettings(defaults: store, systemReduceMotion: false)
        XCTAssertEqual(settings.sensorySafety.preset, .standard)
        XCTAssertEqual(settings.sensorySafety.custom.flashesPerSecond, 3)
        XCTAssertEqual(settings.sensorySafety.custom.intensityLimit, 0)
    }

    func testKeysAreResetAllowedAndBackedUp() {
        for key in SensorySafetySetting.allKeys {
            XCTAssertTrue(AppSettings.allKeys.contains(key), "\(key) is cleared by -uitestResetNotice")
            XCTAssertTrue(LibrarySettingsPolicy.isIncluded(key), "\(key) travels in the FILE-005 backup")
        }
    }

    func testTheBackupRoundTripRestoresTheProfile() {
        let source: UserDefaults = defaults("source")
        let settings = AppSettings(defaults: source, systemReduceMotion: false)
        settings.sensorySafety.preset = .custom
        settings.sensorySafety.flashesPerSecond = 1
        settings.sensorySafety.riseLimitSliderValue = 0.35
        settings.sensorySafety.intensityLimit = 0.4
        let values: [String: LibrarySettingValue] = LibrarySettingsBridge.read(source)
        let target: UserDefaults = defaults("target")
        LibrarySettingsBridge.apply(values, to: target)
        let restored = AppSettings(defaults: target, systemReduceMotion: false)
        XCTAssertEqual(restored.sensorySafety.profile, settings.sensorySafety.profile)
        XCTAssertEqual(restored.safetyClamp, settings.safetyClamp)
    }

    // MARK: Not a parameter (ACC-012-R11)

    func testTheProfileIsNotAModulatableOrExternallyControlledParameter() {
        let ids: [String] = VisualParameterCatalog.descriptors.map { (d: ParameterDescriptor) -> String in d.id.rawValue }
        XCTAssertFalse(ids.contains { (id: String) -> Bool in id.lowercased().contains("safety") || id.lowercased().contains("flash") })
    }
}
