// PresetAuditionBar.swift — roadmap PRE-010 (specs/168-pre-010-quick-audition; R3, R4, R5, R7, R9):
// the browser's bottom bar while a preset is previewed. "Previewing <name>" with Keep and Cancel
// (Escape is Cancel's shortcut); after a failed preview, the notice. Shown as a bottom inset on the
// browser's navigation stack, so the list, its depth and its scroll position never move.
// Announcements are made by PresetCoordinator on the library lane.
import PresetLibrary
import SwiftUI

struct PresetAuditionBar: View {
    @Bindable var presets: PresetCoordinator
    /// Called after Keep committed the preview (the browser closes, as after a tap).
    let onKept: () -> Void

    var body: some View {
        if let audition = presets.audition {
            VStack(alignment: .leading, spacing: 8) {
                if let notice = audition.notice {
                    Text(notice)
                        .font(.footnote)
                        .accessibilityIdentifier("auditionNotice")
                }
                if let shown = audition.showing ?? audition.loading {
                    previewRow(shown, loading: audition.showing == nil || audition.loading != nil)
                } else {
                    noticeOnlyRow
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("auditionBar")
        }
    }

    private func previewRow(_ shown: IndexedPreset, loading: Bool) -> some View {
        let title: String = "Previewing \(shown.name)"
        return ViewThatFits(in: .horizontal) {
            HStack { titleText(title); Spacer(); buttons(loading: loading) }
            VStack(alignment: .leading, spacing: 8) { titleText(title); HStack { buttons(loading: loading) } }   // large type
        }
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .accessibilityIdentifier("auditionName")
    }

    @ViewBuilder private func buttons(loading: Bool) -> some View {
        Button("Cancel", role: .cancel) {
            Task { @MainActor in await presets.cancelAudition() }
        }
        .keyboardShortcut(.cancelAction)   // R4: Escape
        .accessibilityHint("Returns to the preset that was playing")
        .accessibilityIdentifier("auditionCancel")
        Button("Keep") {
            Task { @MainActor in
                if await presets.keepAudition() { onKept() }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(loading)
        .accessibilityHint("Makes this preset the selection")
        .accessibilityIdentifier("auditionKeep")
    }

    private var noticeOnlyRow: some View {
        HStack {
            Spacer()
            Button("OK") { presets.dismissAuditionNotice() }
                .accessibilityIdentifier("auditionNoticeOK")
        }
    }
}
