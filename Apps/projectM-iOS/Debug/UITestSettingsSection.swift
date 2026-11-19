// UITestSettingsSection.swift — DEBUG only: `-uitestSettingsSection <id>` scrolls Settings to the section
// with that ID each time Settings appears, through `ScrollViewReader.scrollTo`, so UI tests reach the
// Color, OSC, MIDI, Show or Storage rows without a dozen drags down a long list (owner rule 7: a UI test
// under 30 s, 2026-11-14). The tests still reveal and assert the same rows. `-uitestSettingsSectionOnce`
// limits it to the first Settings of a launch. The IDs are the `.id(...)`
// strings on SettingsView's sections, top to bottom: "video", "color", "trails", "chromatic" (FX-006), "directionalBlur" (FX-007),
// "radialBlur" (FX-008), "echo" (FX-010), "mosaic" (FX-012), "edgeOutline" (FX-014), "lensDistortion" (FX-016),
// "pixelSort" (FX-011), "vignette" (FX-015), "scanlines" (FX-018), "filmGrain" (FX-017), "effects", "safety",
// "reduceFlashing", "haptics", "performance", "oneHanded", "motion" (CAM-011), "trim", "channel", "gate", "balance", "latency", "osc", "midi", "quality",
// "recording", "recordingFrameRate", "show", "guide", "recentPresets", "storage", "clock" (MED-011), "countdown" (MED-012) (the rest added 2026-11-14 so every UI test that
// works below the first screens opens there; an ID whose section is not shown, such as "video" before a video
// is chosen, scrolls nowhere). An identity only, so Release builds carry no new code: this modifier returns
// the list unchanged there.
// Settings › Storage's list carries it too: "libraryErase" opens Storage at its end (the Erase section, with
// the end of Backup above it), so LibraryEraseUITests reach the Backup and Erase rows without drags (2026-11-14: drags at the
// end of that list in the right margin caught the scroll indicator, which scrubbed the list back to the top).
// `-uitestSettingsJump <id,id…>` adds a small, nearly transparent button per ID (identifier `uitestSettingsJump.<id>`)
// that scrolls the list to that section on a tap, so a test can use the top of Settings (pickers, the visual rows) and
// still reach Storage at the end in one tap: on the iPad panel neither 12 slow nor 30 full-speed swipes reached
// Storage below the photo visual's sections (QA-011 rerun 4, D3 iPadOS 26.5, and pass 4, D2, 2026-11-19).
import SwiftUI

extension View {
    @ViewBuilder
    func uitestSettingsSection(repeated: Bool = false) -> some View {
        #if DEBUG
        modifier(UITestSettingsSection(repeated: repeated))
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
    /// `-uitestSettingsJump storage,show`: the sections a tap scrolls to.
    private let jumps: [String] = {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uitestSettingsJump"), index + 1 < arguments.count else { return [] }
        return arguments[index + 1].split(separator: ",").map(String.init)
    }()
    /// Scroll again 0.3 s and 1 s later: a list in a sheet presented at launch can drop the first scroll
    /// (laid out mid-presentation on a busy Mac: LibraryEraseUITests saw Storage stay at its top, 2026-11-14).
    var repeated = false

    func body(content: Content) -> some View {
        if !jumps.isEmpty {
            ScrollViewReader { (proxy: ScrollViewProxy) in
                scrolled(content, proxy: proxy)
                    .overlay(alignment: .bottomLeading) {   // clear of the rows' trailing switches
                        HStack(spacing: 0) {
                            ForEach(jumps, id: \.self) { (id: String) in
                                Button { proxy.scrollTo(id, anchor: .top) } label: {
                                    Color.gray.frame(width: 44, height: 44)
                                }
                                .opacity(0.05)   // faint, but still hittable for XCUITest
                                .accessibilityLabel("Jump to \(id)")
                                .accessibilityIdentifier("uitestSettingsJump.\(id)")
                            }
                        }
                    }
            }
        } else if target != nil {
            ScrollViewReader { (proxy: ScrollViewProxy) in scrolled(content, proxy: proxy) }
        } else {
            content
        }
    }

    /// The list, scrolled to `-uitestSettingsSection`'s section when Settings appears (as before).
    @ViewBuilder
    private func scrolled(_ content: Content, proxy: ScrollViewProxy) -> some View {
        if let target {
            content.task {
                if once && uitestSettingsSectionUsed { return }
                uitestSettingsSectionUsed = true
                await Task.yield()   // after the list's first layout
                proxy.scrollTo(target, anchor: .top)
                guard repeated else { return }
                for delay in [0.3, 0.7] {
                    try? await Task.sleep(for: .seconds(delay))
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        } else {
            content
        }
    }
}
#endif
