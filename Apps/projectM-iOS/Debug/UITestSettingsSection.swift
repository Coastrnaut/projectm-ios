// UITestSettingsSection.swift — DEBUG only: `-uitestSettingsSection <id>` scrolls Settings to the section
// with that ID each time Settings appears, through `ScrollViewReader.scrollTo`, so UI tests reach the
// Color, OSC, MIDI, Show or Storage rows without a dozen drags down a long list (owner rule 7: a UI test
// under 30 s, 2026-11-14). The tests still reveal and assert the same rows. `-uitestSettingsSectionOnce`
// limits it to the first Settings of a launch. The IDs are the `.id(...)`
// strings on SettingsView's sections ("color", "reduceFlashing", "osc", "midi", "show", "storage"); an
// identity only, so Release builds carry no new code: this modifier returns the list unchanged there.
import SwiftUI

extension View {
    @ViewBuilder
    func uitestSettingsSection() -> some View {
        #if DEBUG
        modifier(UITestSettingsSection())
        #else
        self
        #endif
    }
}

#if DEBUG
/// With `-uitestSettingsSectionOnce` only the first Settings of a launch opens at the section; later ones open at
/// the top, for tests that audit or use the top of Settings after the section (owner rule 7).
@MainActor private var uitestSettingsSectionUsed = false

private struct UITestSettingsSection: ViewModifier {
    private let target: String? = {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uitestSettingsSection"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()
    private let once: Bool = ProcessInfo.processInfo.arguments.contains("-uitestSettingsSectionOnce")

    func body(content: Content) -> some View {
        if let target {
            ScrollViewReader { (proxy: ScrollViewProxy) in
                content.task {
                    if once && uitestSettingsSectionUsed { return }
                    uitestSettingsSectionUsed = true
                    await Task.yield()   // after the list's first layout
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        } else {
            content
        }
    }
}
#endif
