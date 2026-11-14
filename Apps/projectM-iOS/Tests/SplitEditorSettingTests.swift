// SplitEditorSettingTests.swift — UIX-007-T08 (UIX-007-R6, R7; contract split-editor.md C2, C5): the
// remembered editor width, its key lists, the divider's VoiceOver value and the visual's placement.
import CoreGraphics
import LibraryBackup
import ShowControl
import SwiftUI
import XCTest
@testable import projectM_iOS

@MainActor
final class SplitEditorSettingTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "SplitEditorSettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testWidthDefaultsToStandardPersistsAndReadsInvalidAsStandard() {
        let defaults = suite()
        let setting = SplitEditorSetting(defaults: defaults, arguments: [])
        XCTAssertEqual(setting.width, 400)
        XCTAssertNil(defaults.object(forKey: SplitEditorSetting.key), "nothing stored until changed")
        setting.width = 480
        XCTAssertEqual(defaults.double(forKey: "settings.splitEditor.width"), 480)
        XCTAssertEqual(SplitEditorSetting(defaults: defaults, arguments: []).width, 480, "survives a relaunch")
        defaults.set(Double.nan, forKey: SplitEditorSetting.key)
        XCTAssertEqual(SplitEditorSetting(defaults: defaults, arguments: []).width, 400, "invalid → Standard")
        defaults.set(-3.0, forKey: SplitEditorSetting.key)
        XCTAssertEqual(SplitEditorSetting(defaults: defaults, arguments: []).width, 400)
        XCTAssertEqual(SplitEditorSetting(defaults: defaults, arguments: ["-uitestSplitEditorWidth", "333"]).width, 333)
        XCTAssertEqual(SplitEditorSetting(defaults: defaults, arguments: ["-uitestResetNotice"]).width, 400)
        XCTAssertNil(defaults.object(forKey: SplitEditorSetting.key), "the UI-test reset removes it")
    }

    /// R7: device-only (never backed up) and erased with the Settings category.
    func testKeyIsExcludedFromBackupsAndErasedWithSettings() {
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(SplitEditorSetting.key))
        XCTAssertFalse(LibrarySettingsPolicy.isIncluded(SplitEditorSetting.key))
        XCTAssertEqual(LibraryErasePolicy.splitEditorWidthKey, SplitEditorSetting.key)
        XCTAssertTrue(LibraryErasePolicy.settingKeys(.settings).contains(SplitEditorSetting.key))
    }

    /// R6: the divider reads its width and, at a snap point, the snap's name.
    func testDividerValue() {
        XCTAssertEqual(SplitEditorDivider.value(400), "400 points, Standard")
        XCTAssertEqual(SplitEditorDivider.value(320), "320 points, Narrow")
        XCTAssertEqual(SplitEditorDivider.value(437.4), "437 points")
    }

    /// R3: the visual's placement is the layout's output rect at the layout's scale (aspect = window).
    func testPlacementScalesTheFullWindowIntoTheOutputRect() {
        let window = CGSize(width: 1376, height: 1032)
        let layout = SplitEditorLayout(containerWidth: 1376, containerHeight: 1032, editorWidth: 480)
        let placement = SplitEditorHost<EmptyView, EmptyView>.placement(layout, window: window)
        XCTAssertEqual(placement.fullSize, window)
        let shown = CGSize(width: window.width * placement.scale, height: window.height * placement.scale)
        XCTAssertEqual(Double(shown.width / shown.height), 1376.0 / 1032.0, accuracy: 1e-6)
        XCTAssertEqual(Double(shown.width), layout.outputRect.width, accuracy: 1e-6)
        XCTAssertEqual(Double(placement.origin.y), layout.outputRect.y, accuracy: 1e-9)
        XCTAssertEqual(SplitOutputPlacement.identity(window).scale, 1)
    }
}
