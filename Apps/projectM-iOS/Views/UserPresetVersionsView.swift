// UserPresetVersionsView.swift — roadmap PRE-017 (specs/250-pre-017-preset-restore-points; R8): the earlier
// versions of an edited user preset, newest first. Preview shows an earlier text read-only (research D7: an
// earlier text is never handed to a renderer before it is tried again); Revert, after a confirmation, puts it
// back through the edit checks. The text being replaced becomes a version, so a revert can be undone.
import PresetLibrary
import SwiftUI

struct UserPresetVersionsView: View {
    let preset: UserPreset
    let userPresets: UserPresetsCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var list: UserPresetVersionList?
    @State private var confirming: UserPresetVersion?
    @State private var previewing: VersionPreview?
    @State private var reverting = false
    @State private var error: String?

    struct VersionPreview: Identifiable {
        let version: UserPresetVersion
        let text: PresetEditorText?
        var id: String { version.sha256 }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Versions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .disabled(reverting)
                            .accessibilityIdentifier("presetVersionsDone")
                    }
                }
                .alert("Revert to this version?", isPresented: confirmingBinding, presenting: confirming) { (version: UserPresetVersion) in
                    Button("Revert") { Task { await revert(to: version) } }
                        .accessibilityIdentifier("confirmRevert")
                    Button("Cancel", role: .cancel) {}
                } message: { (_: UserPresetVersion) in
                    Text("Your current text is kept as a version.")
                }
                .sheet(item: $previewing) { (preview: VersionPreview) in
                    VersionPreviewView(preview: preview, presetName: preset.name)
                }
        }
        .interactiveDismissDisabled(reverting)
        .accessibilityIdentifier("presetVersions")
        .task {
            guard list == nil else { return }
            list = await userPresets.versions(of: preset)
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { (shown: Bool) in if !shown { confirming = nil } })
    }

    @ViewBuilder private var content: some View {
        if let list {
            List {
                statusSection
                if list.availability == .newerFormat {
                    Text(UserPresetVersionList.newerFormatText).foregroundStyle(.secondary)
                } else if list.versions.isEmpty {
                    Text(UserPresetVersionList.emptyText)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("presetVersionsEmpty")
                } else {
                    Section("Earlier versions") {
                        ForEach(list.versions) { (version: UserPresetVersion) in row(version) }
                    }
                }
            }
            .disabled(reverting)
        } else {
            ProgressView("Loading versions…")
        }
    }

    @ViewBuilder private var statusSection: some View {
        if reverting || error != nil {
            Section {
                if reverting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking the preset…")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("presetVersionsChecking")
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("presetVersionsError")
                }
            }
        }
    }

    private func row(_ version: UserPresetVersion) -> some View {
        let label: String = UserPresetsCoordinator.versionLabel(version, currentName: preset.name)
        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Preview") { Task { await preview(version) } }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Preview version from \(label)")
                    .accessibilityIdentifier("previewVersion")
                Button("Revert") { confirming = version }
                    .buttonStyle(.borderedProminent)
                    .disabled(version.sha256 == preset.sha256)
                    .accessibilityLabel("Revert to version from \(label)")
                    .accessibilityIdentifier("revertVersion")
            }
        }
        .padding(.vertical, 4)
    }

    private func preview(_ version: UserPresetVersion) async {
        let text: PresetEditorText? = await userPresets.versionText(of: preset, version: version)
        previewing = VersionPreview(version: version, text: text)
    }

    private func revert(to version: UserPresetVersion) async {
        guard !reverting else { return }
        reverting = true
        error = nil
        let outcome: PresetEditOutcome = await userPresets.revert(preset, to: version)
        reverting = false
        switch outcome {
        case .saved, .unchanged: dismiss()
        case .refused: error = UserPresetsCoordinator.revertMessage(outcome, name: preset.name)
        }
    }
}

/// An earlier text, read-only, selectable, monospaced, following Dynamic Type.
private struct VersionPreviewView: View {
    let preview: UserPresetVersionsView.VersionPreview
    let presetName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let text = preview.text {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !text.isUTF8 {
                                Text(PresetEditorText.latin1Note).font(.footnote).foregroundStyle(.secondary)
                            }
                            Text(text.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("versionPreviewText")
                        }
                        .padding()
                    }
                } else {
                    Text(PresetEditRefusal.versionUnavailable.message)
                        .foregroundStyle(.secondary)
                        .padding()
                        .accessibilityIdentifier("versionPreviewUnavailable")
                }
            }
            .navigationTitle(presetName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("versionPreviewDone")
                }
            }
        }
    }
}
