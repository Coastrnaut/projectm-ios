// QA-011 device run 2026-11-19 (B07 relaunch): the DEBUG `-uitestDefaults` hook keeps the typed settings through a
// plain relaunch (no `-uitestDefaults`, no `-uitestResetNotice`) and still clears them on the next test's launch.
#if DEBUG
import XCTest
@testable import projectM_iOS

@MainActor
final class UITestDefaultsHookTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "UITestDefaultsHookTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func testTypedValuesAreWritten() {
        withDefaults { (defaults: UserDefaults) -> Void in
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestDefaults", #"{"settings.visual":"text","n":2}"#])
            XCTAssertEqual(defaults.string(forKey: "settings.visual"), "text")
            XCTAssertEqual(defaults.integer(forKey: "n"), 2)
        }
    }

    func testPlainRelaunchKeepsTheTypedValues() {
        withDefaults { (defaults: UserDefaults) -> Void in
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestResetNotice", "-uitestDefaults",
                                                                     #"{"settings.visual":"photo"}"#])
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestDiagnostics", "-autostart", "inAppPlayback"])
            XCTAssertEqual(defaults.string(forKey: "settings.visual"), "photo", "a relaunch keeps what the app stored")
        }
    }

    func testNextTestLaunchClearsThePreviousValues() {
        withDefaults { (defaults: UserDefaults) -> Void in
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestDefaults", #"{"settings.visual":"photo","a":1}"#])
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestDefaults", #"{"settings.visual":"video"}"#])
            XCTAssertEqual(defaults.string(forKey: "settings.visual"), "video")
            XCTAssertNil(defaults.object(forKey: "a"), "one launch's typed keys do not leak into the next")
        }
    }

    func testResetLaunchWithoutTypedValuesClearsThePreviousValues() {
        withDefaults { (defaults: UserDefaults) -> Void in
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestDefaults", #"{"a":1}"#])
            AppCoordinator.applyUITestDefaults(defaults, arguments: ["app", "-uitestResetNotice"])
            XCTAssertNil(defaults.object(forKey: "a"))
            XCTAssertNil(defaults.object(forKey: "uitest.defaults.keys"))
        }
    }
}
#endif
