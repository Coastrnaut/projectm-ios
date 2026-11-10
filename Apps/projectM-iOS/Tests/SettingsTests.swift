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
        let keys = Set(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys)
        XCTAssertEqual(keys, Set(AppSettings.allKeys), "FR-065")
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
