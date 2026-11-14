// OscilloscopeAppTests.swift — VIS-003-T12: the Oscilloscope choice in the app (VIS-003-R10 to R13):
// settings defaults, persistence and safe readings; the host names itself and switches styles in place;
// the fallback notice; a scene captured while it is shown records no native layer. The host test needs
// a Metal device (the simulator renders with the host GPU); it skips without one.
import Metal
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class OscilloscopeAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "OscilloscopeAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testOscilloscopeOptionsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.oscilloscopeLine, .medium, "Medium by default")
        XCTAssertEqual(settings.oscilloscopeWindowMilliseconds, 20, "20 ms by default")
        XCTAssertEqual(OscilloscopeLine.allCases.map(\.title), ["Thin", "Medium", "Thick"])
        XCTAssertEqual(OscilloscopeLine.allCases.map(\.thickness), [0.004, 0.008, 0.016])
        XCTAssertEqual(AppSettings.oscilloscopeWindowChoices, [10, 20, 40])
        settings.visual = .oscilloscope
        settings.oscilloscopeLine = .thick
        settings.oscilloscopeWindowMilliseconds = 40
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "oscilloscope")
        XCTAssertEqual(defaults.string(forKey: "settings.oscilloscope.line"), "thick")
        XCTAssertEqual(defaults.integer(forKey: "settings.oscilloscope.window"), 40)
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .oscilloscope)
        XCTAssertEqual(reloaded.oscilloscopeLine, .thick)
        XCTAssertEqual(reloaded.oscilloscopeWindowMilliseconds, 40)
        settings.oscilloscopeWindowMilliseconds = 33
        XCTAssertEqual(settings.oscilloscopeWindowMilliseconds, 20, "not a choice → 20 ms")
        defaults.set("hairline", forKey: AppSettings.oscilloscopeLineKey)
        defaults.set(15, forKey: AppSettings.oscilloscopeWindowKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.oscilloscopeLine, .medium, "unknown → Medium")
        XCTAssertEqual(bad.oscilloscopeWindowMilliseconds, 20, "unknown → 20 ms")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.oscilloscope.line"))
        XCTAssertTrue(AppSettings.allKeys.contains("settings.oscilloscope.window"))
        XCTAssertTrue(VisualChoice.oscilloscope.isNative)
        XCTAssertEqual(VisualChoice.oscilloscope.title, "Oscilloscope")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .oscilloscope),
                       "Oscilloscope isn't available on this device. Showing projectM.")
    }

    func testOscilloscopeHostNamesItselfAndSwitchesStyles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .oscilloscope(line: .medium, windowMilliseconds: 20),
                                               barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Oscilloscope visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "oscilloscope")
        XCTAssertEqual(host.view.accessibilityValue, "20 ms, Glow off")
        try host.apply(style: .oscilloscope(line: .thick, windowMilliseconds: 40))
        XCTAssertEqual(host.view.accessibilityValue, "40 ms, Glow off")
        host.glow = BloomParameters(enabled: true, intensity: 0.8)
        XCTAssertEqual(host.view.accessibilityValue, "40 ms, Glow on")
        XCTAssertTrue(host.glowActive, "the glow applies to the oscilloscope too")
        host.resume()
        XCTAssertTrue(host.isRunning)
        try host.apply(style: .circular)
        XCTAssertEqual(host.view.accessibilityIdentifier, "circularSpectrum")
        XCTAssertTrue(host.isRunning, "switching kinds keeps the loop running")
        try host.apply(style: .oscilloscope(line: .thin, windowMilliseconds: 10))
        XCTAssertEqual(host.view.accessibilityIdentifier, "oscilloscope")
        XCTAssertEqual(host.barCount, .b32, "the bar count carries over")
        host.pause()
    }

    /// VIS-003-R12: no SCN-001 kind for the oscilloscope yet; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .oscilloscope)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
