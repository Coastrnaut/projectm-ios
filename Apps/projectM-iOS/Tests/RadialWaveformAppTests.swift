// RadialWaveformAppTests.swift — VIS-005-T09: the radial waveform choice in the app (VIS-005-R9 to R11): settings
// defaults, persistence and safe readings; every key list; the host names itself, changes ring and amplitude in
// place (same generator) and applies the palette; a scene captured while it is shown records no native layer.
// The host test needs a Metal device (the simulator renders with the host GPU); it skips without one.
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class RadialWaveformAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "RadialWaveformAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testOptionsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.radialWaveformRing, .medium, "Medium ring by default")
        XCTAssertEqual(settings.radialWaveformAmplitude, .medium, "Medium amplitude by default")
        XCTAssertEqual(RadialWaveformRing.allCases.map(\.title), ["Small", "Medium", "Large"])
        XCTAssertEqual(RadialWaveformAmplitude.allCases.map(\.title), ["Low", "Medium", "High"])
        // VIS-005-R6: every radius R₀ ± A stays within 0.15…0.95 of half the shorter side.
        for ring in RadialWaveformRing.allCases {
            for amplitude in RadialWaveformAmplitude.allCases {
                XCTAssertGreaterThanOrEqual(ring.value - amplitude.value, 0.15 - 1e-12)
                XCTAssertLessThanOrEqual(ring.value + amplitude.value, 0.95 + 1e-12)
            }
        }
        settings.visual = .radialWaveform
        settings.radialWaveformRing = .large
        settings.radialWaveformAmplitude = .high
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "radialWaveform")
        XCTAssertEqual(defaults.string(forKey: "settings.radialWaveform.ring"), "large")
        XCTAssertEqual(defaults.string(forKey: "settings.radialWaveform.amplitude"), "high")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .radialWaveform)
        XCTAssertEqual(reloaded.radialWaveformRing, .large)
        XCTAssertEqual(reloaded.radialWaveformAmplitude, .high)
        defaults.set("huge", forKey: AppSettings.radialWaveformRingKey)
        defaults.set(3, forKey: AppSettings.radialWaveformAmplitudeKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.radialWaveformRing, .medium, "unknown → Medium")
        XCTAssertEqual(bad.radialWaveformAmplitude, .medium, "not a string → Medium")
        XCTAssertTrue(VisualChoice.radialWaveform.isNative)
        XCTAssertFalse(VisualChoice.radialWaveform.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.radialWaveform.title, "Radial Waveform")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .radialWaveform),
                       "Radial Waveform isn't available on this device. Showing projectM.")
    }

    /// VIS-005-R9: the keys are FR-065 settings (reset by `-uitestResetNotice` through `allKeys`) and in the
    /// FILE-005 backup policy.
    func testKeysAreInEveryList() {
        for key in ["settings.radialWaveform.ring", "settings.radialWaveform.amplitude"] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
            XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key), key)
        }
    }

    func testHostNamesItselfAndChangesRingInPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil,
                                               style: .radialWaveform(ring: .medium, amplitude: .medium), barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Radial Waveform visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "radialWaveform")
        XCTAssertEqual(host.view.accessibilityValue, "Medium ring, Medium amplitude, Glow off")
        let generator = try XCTUnwrap(host.radialWaveformGenerator)
        XCTAssertEqual(generator.configuration.baseRadius, 0.55)
        XCTAssertEqual(generator.configuration.amplitude, 0.18)
        try host.apply(style: .radialWaveform(ring: .large, amplitude: .low))
        XCTAssertTrue(host.radialWaveformGenerator === generator, "ring and amplitude change in place")
        XCTAssertEqual(generator.configuration.baseRadius, 0.70)
        XCTAssertEqual(generator.configuration.amplitude, 0.10)
        XCTAssertEqual(host.view.accessibilityValue, "Large ring, Low amplitude, Glow off")
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to the radial waveform")
        host.resume()
        XCTAssertTrue(host.isRunning)
        try host.apply(style: .oscilloscope(line: .medium, windowMilliseconds: 20))
        XCTAssertEqual(host.view.accessibilityIdentifier, "oscilloscope")
        XCTAssertNil(host.radialWaveformGenerator)
        XCTAssertTrue(host.isRunning, "switching kinds keeps the loop running")
        try host.apply(style: .radialWaveform(ring: .small, amplitude: .high))
        XCTAssertEqual(host.radialWaveformGenerator?.configuration.baseRadius, 0.40)
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        XCTAssertEqual(host.barCount, .b32, "the bar count carries over")
        host.pause()
    }

    /// VIS-005-R10: no SCN-001 kind for the radial waveform; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .radialWaveform)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
