// MandalaAppTests.swift — VIS-007-T10: the mandala choice in the app (VIS-007-R5, R9 to R11): the settings'
// defaults, persistence and safe reading; every key list; the host names itself, changes symmetry, mirror and
// petal in place (same generator), applies the palette and Reduce Motion (also to a generator a style change
// builds); a scene captured while it is shown records no native layer. The host test needs a Metal device (the
// simulator renders with the host GPU); it skips without one.
import LibraryBackup
import Metal
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class MandalaAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "MandalaAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.mandalaSymmetry, 6, "6-fold by default")
        XCTAssertFalse(settings.mandalaMirror, "Mirror off by default")
        XCTAssertEqual(settings.mandalaPetal, .petal)
        XCTAssertEqual(MandalaPetalStyle.allCases.map(\.title), ["Petal", "Round", "Spike"])
        settings.visual = .mandala
        settings.mandalaSymmetry = 8
        settings.mandalaMirror = true
        settings.mandalaPetal = .round
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "mandala")
        XCTAssertEqual(defaults.integer(forKey: "settings.mandala.symmetry"), 8)
        XCTAssertTrue(defaults.bool(forKey: "settings.mandala.mirror"))
        XCTAssertEqual(defaults.string(forKey: "settings.mandala.petal"), "round")
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .mandala)
        XCTAssertEqual(reloaded.mandalaSymmetry, 8)
        XCTAssertTrue(reloaded.mandalaMirror)
        XCTAssertEqual(reloaded.mandalaPetal, .round)
        reloaded.mandalaSymmetry = 7
        XCTAssertEqual(reloaded.mandalaSymmetry, 6, "an unsupported symmetry set later reads 6")
        defaults.set(9, forKey: AppSettings.mandalaSymmetryKey)
        defaults.set("star", forKey: AppSettings.mandalaPetalKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.mandalaSymmetry, 6, "unsupported → 6")
        XCTAssertEqual(bad.mandalaPetal, .petal, "unknown → Petal")
        defaults.set("eight", forKey: AppSettings.mandalaSymmetryKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).mandalaSymmetry, 6, "not an Int → 6")
        XCTAssertTrue(VisualChoice.mandala.isNative)
        XCTAssertFalse(VisualChoice.mandala.usesBars, "Bars does not apply")
        XCTAssertEqual(VisualChoice.mandala.title, "Mandala")
        XCTAssertEqual(AppCoordinator.nativeVisualUnavailableMessage(for: .mandala),
                       "Mandala isn't available on this device. Showing projectM.")
    }

    /// VIS-007-R9: the keys are FR-065 settings (reset by `-uitestResetNotice` through `allKeys`) and in the
    /// FILE-005 backup policy.
    func testKeysAreInEveryList() {
        for key in ["settings.mandala.symmetry", "settings.mandala.mirror", "settings.mandala.petal"] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
            XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(key), key)
        }
    }

    func testHostNamesItselfChangesInPlaceAndFollowsReduceMotion() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .mandala(symmetry: 6, mirror: false, petal: .petal),
                                               barCount: .b32)
        XCTAssertEqual(host.view.accessibilityLabel, "Mandala visualization")
        XCTAssertEqual(host.view.accessibilityIdentifier, "mandala")
        XCTAssertEqual(host.view.accessibilityValue, "6-fold, Mirror off, Petal, Glow off")
        let generator = try XCTUnwrap(host.mandalaGenerator)
        XCTAssertEqual(generator.configuration.symmetry, 6)
        XCTAssertFalse(generator.configuration.reduceMotion)
        try host.apply(style: .mandala(symmetry: 8, mirror: true, petal: .spike))
        XCTAssertTrue(host.mandalaGenerator === generator, "symmetry, mirror and petal change in place")
        XCTAssertEqual(generator.configuration.symmetry, 8)
        XCTAssertTrue(generator.configuration.mirror)
        XCTAssertEqual(generator.configuration.petalStyle, .spike)
        XCTAssertEqual(host.view.accessibilityValue, "8-fold, Mirror on, Spike, Glow off")
        host.reduceMotion = true
        XCTAssertTrue(generator.configuration.reduceMotion, "Reduce Motion halves the turn")
        XCTAssertEqual(generator.configuration.effectiveTurnsPerSecond, MandalaConfiguration.defaultTurnsPerSecond / 2)
        host.palette = .colorBlindSafe
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe, "ACC-003-R13 applies to the mandala")
        try host.apply(style: .circular)
        XCTAssertNil(host.mandalaGenerator)
        try host.apply(style: .mandala(symmetry: 12, mirror: false, petal: .round))
        let rebuilt = try XCTUnwrap(host.mandalaGenerator)
        XCTAssertEqual(rebuilt.configuration.symmetry, 12)
        XCTAssertTrue(rebuilt.configuration.reduceMotion, "a new generator gets Reduce Motion too")
        XCTAssertEqual(host.generatorPalette, .colorBlindSafe)
        host.reduceMotion = false
        XCTAssertFalse(rebuilt.configuration.reduceMotion)
    }

    /// VIS-007-R10: no SCN-001 kind for the mandala; a scene records no native layer.
    func testSceneCaptureRecordsNoNativeLayer() {
        let inputs = SceneAutosaveFixtures.inputs(visual: .mandala)
        let document = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(document.layers.map(\.kind), [])
    }
}
