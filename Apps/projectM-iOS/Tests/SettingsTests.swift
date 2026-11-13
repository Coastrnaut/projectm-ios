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
        settings.glowEnabled = true            // FX-001-R11
        settings.glowIntensity = 0.8
        settings.glowRadius = 0.03
        settings.glowThreshold = 0.5
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

    /// FX-001-T17 (FX-001-R4, R11): the glow settings, their defaults, persistence and safe readings.
    func testGlowSettingsDefaultPersistAndClamp() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.glowEnabled, "Glow is off by default")
        XCTAssertEqual(settings.glowIntensity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(settings.glowRadius, 0.02, accuracy: 1e-6)
        XCTAssertEqual(settings.glowThreshold, 0.7, accuracy: 1e-6)
        XCTAssertTrue(settings.glowParameters.isPassThrough)

        settings.glowEnabled = true
        settings.glowIntensity = 0.9
        settings.glowRadius = 0.05
        settings.glowThreshold = 0.4
        XCTAssertTrue(defaults.bool(forKey: "settings.circularSpectrum.glow"))
        XCTAssertEqual(defaults.double(forKey: "settings.circularSpectrum.glowIntensity"), 0.9, accuracy: 1e-6)
        XCTAssertEqual(defaults.double(forKey: "settings.circularSpectrum.glowRadius"), 0.05, accuracy: 1e-6)
        XCTAssertEqual(defaults.double(forKey: "settings.circularSpectrum.glowThreshold"), 0.4, accuracy: 1e-6)
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertTrue(reloaded.glowEnabled)
        let p = reloaded.glowParameters
        XCTAssertTrue(p.enabled)
        XCTAssertEqual(p.intensity, 0.9, accuracy: 1e-6)
        XCTAssertEqual(p.radius, 0.05, accuracy: 1e-6)
        XCTAssertEqual(p.threshold, 0.4, accuracy: 1e-6)
        XCTAssertEqual(p.knee, 0.5, accuracy: 1e-6, "the knee is not a setting")

        // Out of range and NaN.
        settings.glowIntensity = 7
        XCTAssertEqual(settings.glowIntensity, 1, accuracy: 1e-6)
        settings.glowRadius = -1
        XCTAssertEqual(settings.glowRadius, 0.005, accuracy: 1e-6)
        defaults.set(Double.nan, forKey: AppSettings.glowThresholdKey)
        defaults.set(42.0, forKey: AppSettings.glowRadiusKey)
        defaults.set("x", forKey: AppSettings.glowIntensityKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.glowThreshold, 0.7, accuracy: 1e-6, "NaN reads the default")
        XCTAssertEqual(bad.glowRadius, 0.06, accuracy: 1e-6, "clamped")
        XCTAssertEqual(bad.glowIntensity, 0.5, accuracy: 1e-6, "not a number reads the default")

        for key in ["settings.circularSpectrum.glow", "settings.circularSpectrum.glowIntensity",
                    "settings.circularSpectrum.glowRadius", "settings.circularSpectrum.glowThreshold"] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
        }
    }
}
