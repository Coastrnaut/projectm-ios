// SplitEditorSetting.swift — UIX-007-R7 (specs/205-uix-007-split-preview-editor, data-model.md): the
// iPad split editor's remembered width.
//
// One Double (points), key `settings.splitEditor.width`; absent, non-finite or ≤ 0 → Standard (400 pt).
// It depends on this device's screen, so it is never backed up (FILE-005 `excludedKeys`) and is erased
// with the Settings category (FILE-011); `-uitestResetNotice` removes it. DEBUG
// `-uitestSplitEditorWidth <pt>` stores a width at launch (UI tests, contract C5). The stored value is
// the user's choice; the layout clamps it to the current window without rewriting it.
import Foundation
import Observation
import ShowControl

@MainActor
@Observable
final class SplitEditorSetting {
    static let key = "settings.splitEditor.width"

    @ObservationIgnored private let defaults: UserDefaults

    /// The editor width the user last chose, in points.
    var width: Double {
        didSet { defaults.set(width, forKey: Self.key) }
    }

    init(defaults: UserDefaults, arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: Standard
        }
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitestSplitEditorWidth"), i + 1 < arguments.count,
           let value = Double(arguments[i + 1]) {
            defaults.set(value, forKey: Self.key)
        }
        #endif
        self.defaults = defaults
        width = Self.stored(in: defaults)
    }

    /// The stored width, Standard when absent or invalid.
    static func stored(in defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: key) != nil else { return SplitEditorLayout.defaultEditorWidth }
        let value: Double = defaults.double(forKey: key)
        return value.isFinite && value > 0 ? value : SplitEditorLayout.defaultEditorWidth
    }
}
