// Task T103: settings defaults and persistence (FR-048, FR-072, FR-065) and the bundled license
// manifest (FR-067).
import XCTest
@testable import projectM_iOS

@MainActor
final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testPerformanceOverlayIsOffByDefaultAndPersists() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.showsPerformanceOverlay, "FR-048: off by default")
        settings.showsPerformanceOverlay = true
        XCTAssertTrue(AppSettings(defaults: defaults, systemReduceMotion: false).showsPerformanceOverlay)
    }

    func testReduceFlashingFollowsReduceMotionUntilChosen() {
        XCTAssertFalse(AppSettings(defaults: defaults, systemReduceMotion: false).reduceFlashing)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: true)
        XCTAssertTrue(settings.reduceFlashing, "FR-072: on by default with Reduce Motion")
        XCTAssertTrue(settings.reduceFlashingFollowsSystem)
        settings.systemReduceMotion = false
        XCTAssertFalse(settings.reduceFlashing, "still following the system")

        settings.reduceFlashing = true
        settings.systemReduceMotion = false
        XCTAssertTrue(settings.reduceFlashing, "the user's choice wins")
        XCTAssertTrue(AppSettings(defaults: defaults, systemReduceMotion: false).reduceFlashing, "persisted")

        settings.followSystemForReduceFlashing()
        XCTAssertFalse(settings.reduceFlashing)
        XCTAssertNil(defaults.object(forKey: AppSettings.reduceFlashingKey))
    }

    func testOnlyTheSettingsKeysAreWritten() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.showsPerformanceOverlay = true
        settings.reduceFlashing = true
        settings.presetScope = "all"
        settings.visual = .circularSpectrum
        settings.circularSpectrumBars = 32
        let keys = Set(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys)
        XCTAssertEqual(keys, Set(AppSettings.allKeys), "FR-065")
    }

    /// VIS-001-T19 (VIS-001-R11): the visual choice and the bar count, with safe readings of bad values.
    func testVisualChoiceDefaultsToProjectMAndPersists() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.visual, .projectM, "projectM stays the default")
        settings.visual = .circularSpectrum
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "circularSpectrum")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .circularSpectrum, "persisted")
        defaults.set("kaleidoscope", forKey: AppSettings.visualKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .projectM, "unknown → projectM")
    }

    func testCircularSpectrumBarsDefaultTo64AndPersist() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.circularSpectrumBars, 64)
        settings.circularSpectrumBars = 16
        XCTAssertEqual(defaults.integer(forKey: "settings.circularSpectrum.bars"), 16)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).circularSpectrumBars, 16)
        defaults.set(24, forKey: AppSettings.circularSpectrumBarsKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).circularSpectrumBars, 64, "not a band count → 64")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.visual"))
        XCTAssertTrue(AppSettings.allKeys.contains("settings.circularSpectrum.bars"))
    }

    func testTheBundledLicenseManifestIsComplete() throws {
        let catalog = try XCTUnwrap(LicenseCatalog.bundled(Bundle(for: AppSettings.self)) ?? LicenseCatalog.bundled())
        let ids = Set(catalog.components.map(\.id))
        for required in ["app", "projectm", "glad", "glm", "hlslparser", "projectm-eval", "stb_image", "angle-ANGLE", "presets"] {
            XCTAssertTrue(ids.contains(required), required)
        }
        for component in catalog.components {
            XCTAssertNotEqual(LicenseCatalog.text(of: component), "License text missing.", component.id)
        }
        XCTAssertTrue(catalog.lgplNote.text.contains("github.com/Coastrnaut/projectm"))
        let engine = try XCTUnwrap(catalog.components.first { $0.id == "projectm" })
        XCTAssertTrue(LicenseCatalog.text(of: engine).contains("GNU LESSER GENERAL PUBLIC LICENSE"))
    }
}
