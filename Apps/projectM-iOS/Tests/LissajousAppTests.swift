// LissajousAppTests.swift — VIS-004-T10: the Lissajous choice in the app (VIS-004-R9 to R12, R14): settings
// defaults, persistence and safe readings; every key list; the host names itself, switches plot in place and
// applies the ACC-012-capped persistence half-life; a scene captured while it is shown records no native
// layer. The host tests need a Metal device (the simulator renders with the host GPU); they skip without one.
import FlashSafety
import LibraryBackup
import Metal
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class LissajousAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "LissajousAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testLissajousOptionsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.lissajousMode, .xy, "X/Y by default")
        XCTAssertFalse(settings.lissajousPersistence, "persistence off by default")
        XCTAssertEqual(LissajousMode.allCases.map(\.title), ["X/Y", "Mid/Side"])
        settings.visual = .lissajous
        settings.lissajousMode = .midSide
        settings.lissajousPersistence = true
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "lissajous")
        XCTAssertEqual(defaults.string(forKey: "settings.lissajous.mode"), "midSide")
        XCTAssertTrue(defaults.bool(forKey: "settings.lissajous.persistence"))
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .lissajous)
        XCTAssertEqual(reloaded.lissajousMode, .midSide)
        XCTAssertTrue(reloaded.lissajousPersistence)
        defaults.set("polar", forKey: AppSettings.lissajousModeKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).lissajousMode, .xy, "unknown → X/Y")
        XCTAssertTrue(VisualChoice.lissajous.isNative)
        XCTAssertFalse(VisualChoice.lissajous.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.lissajous.title, "Lissajous")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .lissajous),
                       "Lissajous isn't available on this device. Showing projectM.")
    }

    /// VIS-004-R11: the keys are FR-065 settings (reset by `-uitestResetNotice` through `allKeys`) and in the
    /// FILE-005 backup policy.
    func testKeysAreInEveryList() {
        for key in ["settings.lissajous.mode", "settings.lissajous.persistence"] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
            XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key), key)
        }
    }

    func testHostNamesItselfSwitchesPlotAndCapsPersistence() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .lissajous(mode: .xy, persistence: false),
                                               barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Lissajous visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "lissajous")
        XCTAssertEqual(host.view.accessibilityValue, "X/Y, Persistence off, Glow off")
        XCTAssertEqual(host.lissajousPersistenceHalfLife, 0)
        try host.apply(style: .lissajous(mode: .midSide, persistence: true))
        XCTAssertEqual(host.view.accessibilityValue, "Mid/Side, Persistence on, Glow off")
        XCTAssertEqual(host.lissajousPersistenceHalfLife, 0.2, "the nominal half-life under Standard")
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        host.safetyClamp = strict
        XCTAssertEqual(host.lissajousPersistenceHalfLife ?? -1, 0.125, accuracy: 1e-12, "Strict: intensity 0.25 × 0.5 s")
        host.safetyClamp = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
        XCTAssertLessThanOrEqual(host.lissajousPersistenceHalfLife ?? 1, 0.25, "Reduce flashing caps it at 0.25 s")
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to the Lissajous")
        host.resume()
        XCTAssertTrue(host.isRunning)
        try host.apply(style: .oscilloscope(line: .medium, windowMilliseconds: 20))
        XCTAssertEqual(host.view.accessibilityIdentifier, "oscilloscope")
        XCTAssertNil(host.lissajousPersistenceHalfLife)
        XCTAssertTrue(host.isRunning, "switching kinds keeps the loop running")
        try host.apply(style: .lissajous(mode: .xy, persistence: true))
        XCTAssertEqual(host.lissajousPersistenceHalfLife, 0.2, "a new generator gets the clamped half-life")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        XCTAssertEqual(host.barCount, .b32, "the bar count carries over")
        host.pause()
    }

    /// VIS-004-R12: no SCN-001 kind for the Lissajous; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .lissajous)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
