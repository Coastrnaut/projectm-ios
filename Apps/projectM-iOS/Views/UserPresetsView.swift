// UserPresetsView.swift — My Presets: the presets the user imported, their information, and
// Quarantine (roadmap PRE-012, specs/008-pre-012-preset-import-validation; PRE-012-R1, R13, R20,
// R24, R28, R29; US1, US2, US4).
//
// * "Import Preset…" opens the system Files picker for one `.milk` file. The file is copied,
//   checked and tried off screen before it is listed; the result is announced, and shown in an
//   alert when it needs attention (warnings, waiting, quarantined, refused).
// * Playable presets are ordinary preset rows: tap to play (My Presets becomes the scope), star,
//   add to a collection; plus Information and Remove.
// * Presets waiting for their check and quarantined files are listed apart and cannot be played.
import PresetLibrary
import SwiftUI
import UniformTypeIdentifiers

/// Where the browser's My Presets screens lead.
enum UserPresetRoute: Hashable {
    case list
    case quarantine
}

struct UserPresetsView: View {
    @Bindable var presets: PresetCoordinator
    @Bindable var userPresets: UserPresetsCoordinator
    let onChoose: (IndexedPreset, PresetScope) -> Void
    /// Closes the whole browser.
    let onDone: () -> Void

    @State private var importing = false
    @State private var showingInfo: UserPreset?
    @State private var removing: UserPreset?

    /// `.milk` has no system type; plain data keeps such files selectable. The extension is
    /// checked again when the file is imported.
    private static let pickerTypes: [UTType] = [UTType(filenameExtension: "milk"), .data].compactMap { $0 }

    var body: some View {
        List {
            if let unavailable = userPresets.unavailableMessage {
                Text(unavailable)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("userPresetsUnavailable")
            }
            if let notice = userPresets.notice {
                Section {
                    Text(notice).accessibilityIdentifier("userPresetsNotice")
                    Button("Dismiss") { userPresets.dismissNotice() }
                }
            }
            if userPresets.isImporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking the preset…")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("importProgress")
            }
            Section {
                if userPresets.playable.isEmpty && userPresets.pending.isEmpty && !userPresets.isImporting {
                    Text(UserPresetText.empty)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("userPresetsEmpty")
                }
                ForEach(playableRows, id: \.record.id) { row in
                    PresetRow(presets: presets, preset: row.indexed, showsPack: false,
                              user: PresetRow.UserActions(info: { showingInfo = row.record }, remove: { removing = row.record })) {
                        onChoose(row.indexed, .user)
                    }
                }
            }
            if !userPresets.pending.isEmpty {
                Section(UserPresetText.pending) {
                    ForEach(userPresets.pending) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text("It will be checked before it can play.").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(UserPresetsCoordinator.pendingLabel(name: preset.name))
                        .accessibilityIdentifier("pendingPreset:\(preset.name)")
                        .accessibilityAction(named: "Remove") { removing = preset }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { removing = preset } label: { Label("Remove", systemImage: "trash") }.tint(.red)
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: UserPresetRoute.quarantine) {
                    HStack {
                        Text("Quarantine")
                        Spacer()
                        Text(userPresets.quarantined.count.formatted()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(UserPresetsCoordinator.quarantineRowLabel(count: userPresets.quarantined.count))
                }
                .accessibilityIdentifier("quarantineLink")
            }
        }
        .navigationTitle(UserPresetText.scopeTitle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    importing = true
                } label: {
                    Label("Import Preset…", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(userPresets.isImporting || userPresets.unavailableMessage != nil)
                .accessibilityIdentifier("importPreset")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.pickerTypes, allowsMultipleSelection: false) { result in
            let picked = result.flatMap { urls -> Result<URL, any Error> in
                urls.first.map { .success($0) } ?? .failure(CocoaError(.userCancelled))
            }
            Task { await userPresets.importPicked(picked) }
        }
        .importResultAlert(userPresets)
        .sheet(item: $showingInfo) { preset in UserPresetInfoView(preset: preset) }
        .alert("Remove “\(removing?.name ?? "")”?",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { preset in
            Button("Remove Preset", role: .destructive) { Task { await userPresets.remove(preset) } }
                .accessibilityIdentifier("confirmRemovePreset")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The app's copy of this preset is deleted. The file you imported it from is not touched.")
        }
    }

    /// Playable records with their library entries (the entry is what plays and gets starred).
    private var playableRows: [(record: UserPreset, indexed: IndexedPreset)] {
        userPresets.playable.compactMap { record in
            presets.library?.preset(id: record.id).map { (record, $0) }
        }
    }
}

extension View {
    /// The result of an import that needs the user's attention (PRE-012-R28).
    func importResultAlert(_ userPresets: UserPresetsCoordinator) -> some View {
        alert("Import Preset",
              isPresented: Binding(get: { userPresets.resultMessage != nil }, set: { if !$0 { userPresets.resultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(userPresets.resultMessage ?? "")
        }
    }
}

/// Files that failed a check: listed with the reason, never playable, deletable (PRE-012-R13, R20, R24).
struct PresetQuarantineView: View {
    @Bindable var userPresets: UserPresetsCoordinator
    let onDone: () -> Void

    var body: some View {
        List {
            Section {
                Text(userPresets.quarantined.isEmpty ? UserPresetText.quarantineEmpty : UserPresetText.quarantineExplanation)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(userPresets.quarantined.isEmpty ? "quarantineEmpty" : "quarantineExplanation")
            }
            ForEach(userPresets.quarantined) { preset in
                let reason = preset.quarantine?.message ?? "This preset could not be used."
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.originalFileName)
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("quarantineReason:\(preset.originalFileName)")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(UserPresetsCoordinator.quarantinedFileLabel(fileName: preset.originalFileName, reason: reason))
                    .accessibilityIdentifier("quarantined:\(preset.originalFileName)")
                    .accessibilityAction(named: "Delete") { Task { await userPresets.remove(preset) } }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await userPresets.remove(preset) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(preset.originalFileName)")
                    .accessibilityIdentifier("deleteQuarantined:\(preset.originalFileName)")
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await userPresets.remove(preset) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Quarantine")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        .importResultAlert(userPresets)
    }
}

/// What the app knows about an imported preset (PRE-012-R11, R12; US4). Nothing here is guessed
/// except the author, which is marked as coming from the file name.
struct UserPresetInfoView: View {
    let preset: UserPreset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    row("Name", preset.name)
                    row("File name", preset.originalFileName)
                    row("Size", UserPresetsCoordinator.byteCountText(preset.byteCount))
                    row("Imported", preset.importedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Author and license") {
                    row("Author", preset.author.isEmpty ? "Unknown" : "\(preset.author) (from the file name)")
                    Text(PresetLicenseMetadata.rightsText)
                        .accessibilityIdentifier("presetRights")
                    if preset.license.linesFound.isEmpty {
                        Text(PresetLicenseMetadata.noLicenseText)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("presetNoLicense")
                    } else {
                        ForEach(Array(preset.license.linesFound.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Found in the file").font(.caption).foregroundStyle(.secondary)
                                Text(item.element).font(.callout.monospaced())
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("presetLicenseLine")
                        }
                    }
                }
                Section("Checks") {
                    if preset.warnings.isEmpty {
                        Text("No warnings.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(preset.warnings.enumerated()), id: \.offset) { item in
                        Label(item.element.message, systemImage: "exclamationmark.triangle")
                            .accessibilityIdentifier("presetWarning")
                    }
                    Text(preset.provenOnScreen ? "Checked off screen and shown without a problem."
                                               : "Checked off screen. Not shown for long enough yet to count as proven.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Preset Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("presetInfo")
    }

    /// A label above its value, so long values wrap at any text size.
    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}
