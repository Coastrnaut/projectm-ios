// MIDIProfilesSection.swift — the Profiles section of MIDI Mappings (MIDI-012-R8, R10, R12; contract P3).
// Save Current and Import…, the device suggestion, one row per profile (name, mapping count, "In use") with Apply and a
// More menu (Rename…, Export…, Link to Device, Delete…), and the last message. The rename alert, the delete
// confirmation, the file mover and the file picker are attached to the screen's List (`midiProfilesPresentation`), as
// FILE-005 does, because presentations on lazily built rows are unreliable. Standard rows and text that wraps, so
// Dynamic Type and VoiceOver apply; nothing animates. Small bodies (CI's Xcode 26 type-check budget).
import PerformanceControl
import SwiftUI
import UniformTypeIdentifiers

struct MIDIProfilesSection: View {
    var profiles: MIDIProfilesCoordinator

    static let footer: String = "A profile saves all mappings under a name, for example per controller. Apply replaces the current mappings (Undo restores them). Exported files hold the mappings only, never a device. Profiles stay on this device: library backups do not include them; Erase Settings removes them."

    var body: some View {
        Section {
            MIDIProfileActionsRow(profiles: profiles)
            if let suggestion = profiles.suggestion {
                MIDIProfileSuggestionRow(profiles: profiles, profile: suggestion.profile, inputName: suggestion.inputName)
            }
            ForEach(profiles.rows) { (row: MIDIProfileRow) in
                MIDIProfileRowView(profiles: profiles, row: row)
            }
            if let readError = profiles.readError {
                Text(MIDIProfilesCoordinator.unreadableText + " (" + readError.message + ")")
                    .font(.footnote)
                    .accessibilityIdentifier("midiProfilesUnreadable")
            }
            if let message = profiles.message {
                Text(message)
                    .font(.footnote)
                    .accessibilityIdentifier("midiProfilesMessage")
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text(Self.footer)
        }
    }
}

private struct MIDIProfileActionsRow: View {
    var profiles: MIDIProfilesCoordinator

    var body: some View {
        HStack {
            Button("Save Current") { profiles.saveCurrent() }
                .buttonStyle(.borderless)
                .disabled(!profiles.canSave)
                .accessibilityLabel("Save current mappings as a profile")
                .accessibilityIdentifier("midiProfileSaveCurrent")
            Spacer()
            Button("Import…") { profiles.showImporter = true }
                .buttonStyle(.borderless)
                .disabled(!profiles.canImport)
                .accessibilityLabel("Import a profile file")
                .accessibilityIdentifier("midiProfileImport")
        }
    }
}

/// MIDI-012-R8: a linked input is listed; the user decides.
private struct MIDIProfileSuggestionRow: View {
    var profiles: MIDIProfilesCoordinator
    let profile: MIDIProfile
    let inputName: String

    private var text: String { "Suggested for " + inputName + ": " + profile.name }

    var body: some View {
        HStack {
            Text(text)
            Spacer()
            Button("Apply") { profiles.apply(id: profile.id) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Apply " + profile.name)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("midiProfileSuggestion")
    }
}

private struct MIDIProfileRowView: View {
    var profiles: MIDIProfilesCoordinator
    let row: MIDIProfileRow

    var body: some View {
        HStack {
            LabeledContent(row.name, value: row.detail)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityIdentifier("midiProfile." + row.name)
            Button("Apply") { profiles.apply(id: row.id) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Apply " + row.name)
                .accessibilityIdentifier("midiProfileApply." + row.name)
            MIDIProfileMoreMenu(profiles: profiles, row: row)
        }
    }
}

private struct MIDIProfileMoreMenu: View {
    var profiles: MIDIProfilesCoordinator
    let row: MIDIProfileRow

    var body: some View {
        Menu {
            Button("Rename…") { profiles.startRename(row.id) }
            Button("Export…") { profiles.prepareExport(id: row.id) }
            MIDIProfileLinkMenu(profiles: profiles, row: row)
            Button("Delete…", role: .destructive) { profiles.deleteID = row.id }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(profiles.readError != nil)
        .accessibilityLabel("More for " + row.name)
        .accessibilityIdentifier("midiProfileMore." + row.name)
    }
}

private struct MIDIProfileLinkMenu: View {
    var profiles: MIDIProfilesCoordinator
    let row: MIDIProfileRow

    var body: some View {
        Menu("Link to Device") {
            ForEach(profiles.linkTargets) { (target: MIDILinkTarget) in
                Button(target.name) { profiles.link(id: row.id, to: target.endpoint) }
            }
            if row.linkText != nil {
                Button("Unlink") { profiles.link(id: row.id, to: nil) }
            }
        }
    }
}

/// The rename alert, delete confirmation, file mover and file picker, attached to the MIDI Mappings List.
struct MIDIProfilesPresentation: ViewModifier {
    @Bindable var profiles: MIDIProfilesCoordinator

    private var renameShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in profiles.renameID != nil },
                      set: { (shown: Bool) -> Void in if !shown { profiles.renameID = nil } })
    }

    private var deleteShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in profiles.deleteID != nil },
                      set: { (shown: Bool) -> Void in if !shown { profiles.deleteID = nil } })
    }

    private var deleteTitle: String { "Delete “" + profiles.profileName(profiles.deleteID) + "”? This cannot be undone." }

    func body(content: Content) -> some View {
        content
            .alert("Rename Profile", isPresented: renameShown) {
                TextField("Name", text: $profiles.renameText)
                    .accessibilityIdentifier("midiProfileRenameField")
                Button("Rename") { profiles.finishRename() }
                Button("Cancel", role: .cancel) { profiles.renameID = nil }
            }
            .confirmationDialog(deleteTitle, isPresented: deleteShown, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { profiles.confirmDelete() }
            }
            .modifier(MIDIProfileFilePresentation(profiles: profiles))
    }
}

/// Export (file mover) and Import (file picker: any data file; the content decides, MIDI-012-R12).
private struct MIDIProfileFilePresentation: ViewModifier {
    @Bindable var profiles: MIDIProfilesCoordinator

    func body(content: Content) -> some View {
        content
            .fileMover(isPresented: $profiles.showMover, file: profiles.exportFile) { (result: Result<URL, any Error>) in
                profiles.exportFinished(result)
            } onCancellation: {
                profiles.exportCancelled()
            }
            .fileImporter(isPresented: $profiles.showImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) {
                (result: Result<[URL], any Error>) in
                if case let .success(urls) = result, let url = urls.first { profiles.importFile(at: url) }
            }
    }
}

extension View {
    /// MIDI-012: the Profiles section's presentations (nil: none).
    @ViewBuilder
    func midiProfilesPresentation(_ profiles: MIDIProfilesCoordinator?) -> some View {
        if let profiles { modifier(MIDIProfilesPresentation(profiles: profiles)) } else { self }
    }
}
