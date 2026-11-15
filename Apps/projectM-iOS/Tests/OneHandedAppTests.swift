// OneHandedAppTests.swift — ACC-009-T08 (specs/244-acc-009-one-handed-mode; R1, R6, R9; contract C3): the one-handed
// layout preference. The geometry and the action sets are tested in ShowControl (OneHandedLayoutTests); the layout in
// the running app by OneHandedUITests.
import LibraryBackup
import ShowControl
import XCTest
@testable import projectM_iOS

@MainActor
final class OneHandedAppTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "OneHandedAppTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testOffByDefaultAndStoresTheHand() {
        let defaults: UserDefaults = freshDefaults()
        let setting = OneHandedSetting(defaults: defaults, isPhone: true)
        XCTAssertNil(setting.hand)
        XCTAssertFalse(setting.isActive)
        setting.hand = .right
        XCTAssertEqual(defaults.string(forKey: OneHandedSetting.key), "right")
        XCTAssertTrue(setting.isActive)
        XCTAssertEqual(OneHandedSetting(defaults: defaults, isPhone: true).hand, .right, "read back at launch")
        setting.hand = nil
        XCTAssertNil(defaults.object(forKey: OneHandedSetting.key), "Off removes the key")
    }

    func testUnknownStoredValueIsOff() {
        let defaults: UserDefaults = freshDefaults()
        defaults.set("both", forKey: OneHandedSetting.key)
        XCTAssertNil(OneHandedSetting(defaults: defaults, isPhone: true).hand)
    }

    /// R6: on iPad a stored hand (from a backup) is ignored.
    func testIPadIgnoresTheChoice() {
        let defaults: UserDefaults = freshDefaults()
        defaults.set("left", forKey: OneHandedSetting.key)
        let setting = OneHandedSetting(defaults: defaults, isPhone: false)
        XCTAssertEqual(setting.hand, .left, "kept, so it travels back to an iPhone")
        XCTAssertFalse(setting.isActive)
    }

    /// R9: the key is the FILE-005 backup's (erased with Settings) and the device-test allow list's.
    func testKeyIsBackedUp() throws {
        XCTAssertEqual(OneHandedSetting.key, "settings.controls.oneHanded")
        XCTAssertTrue(LibrarySettingsPolicy.includedKeys.contains(OneHandedSetting.key))
    }
}
