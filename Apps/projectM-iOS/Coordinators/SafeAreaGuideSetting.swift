// SafeAreaGuideSetting.swift — OUT-005-R6 (spec specs/258-out-005-safe-area-guides, contract C3): the
// safe-area guides preference (Settings → Performance → Safe-area guides).
//
// Four keys: `settings.visualizer.guides` (Bool, off), `settings.visualizer.guides.actionSafe` (Int 80…100,
// 93), `settings.visualizer.guides.titleSafe` (Int 70…100, 90) and `settings.visualizer.guides.centreCross`
// (Bool, off). Absent reads the default; written on change only. A preference like UIX-013's HUD: backed up
// with the library settings (FILE-005 `includedKeys`), erased with Settings (FILE-011), removed by
// `-uitestResetNotice`. The guides are drawn on the device only (OUT-005-R1); nothing here reaches output.
import Foundation
import Observation
import PresentationLifecycle

@MainActor
@Observable
final class SafeAreaGuideSetting {
    static let enabledKey = "settings.visualizer.guides"
    static let actionKey = "settings.visualizer.guides.actionSafe"
    static let titleKey = "settings.visualizer.guides.titleSafe"
    static let crossKey = "settings.visualizer.guides.centreCross"
    static let allKeys: [String] = [enabledKey, actionKey, titleKey, crossKey]

    static let sectionTitle = "Safe-Area Guides"
    static let title = "Show guides"
    static let actionTitle = "Action safe"
    static let titleSafeTitle = "Title safe"
    static let crossTitle = "Centre cross"
    static let footer = "Outlines the action-safe and title-safe areas of the output (93 % and 90 % by default) on this "
        + "screen while you compose. With an external display they follow its shape. The guides are never on an "
        + "external display, in recordings or in saved frames."

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet { if isEnabled != oldValue { defaults.set(isEnabled, forKey: Self.enabledKey) } }
    }
    var actionPercent: Int {
        didSet {
            let clamped: Int = SafeAreaGuideChoice.clampAction(actionPercent)
            if clamped != actionPercent { actionPercent = clamped }
            if actionPercent != oldValue { defaults.set(actionPercent, forKey: Self.actionKey) }
        }
    }
    var titlePercent: Int {
        didSet {
            let clamped: Int = SafeAreaGuideChoice.clampTitle(titlePercent)
            if clamped != titlePercent { titlePercent = clamped }
            if titlePercent != oldValue { defaults.set(titlePercent, forKey: Self.titleKey) }
        }
    }
    var showsCentreCross: Bool {
        didSet { if showsCentreCross != oldValue { defaults.set(showsCentreCross, forKey: Self.crossKey) } }
    }

    var choice: SafeAreaGuideChoice {
        SafeAreaGuideChoice(actionPercent: actionPercent, titlePercent: titlePercent, showsCentreCross: showsCentreCross)
    }

    init(defaults: UserDefaults) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            for key in Self.allKeys { defaults.removeObject(forKey: key) }   // the UI-test reset: defaults
        }
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let action: Int = (defaults.object(forKey: Self.actionKey) as? Int) ?? SafeAreaGuideChoice.defaultActionPercent
        let title: Int = (defaults.object(forKey: Self.titleKey) as? Int) ?? SafeAreaGuideChoice.defaultTitlePercent
        actionPercent = SafeAreaGuideChoice.clampAction(action)
        titlePercent = SafeAreaGuideChoice.clampTitle(title)
        showsCentreCross = defaults.bool(forKey: Self.crossKey)
    }
}
