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
// * PRE-015 (specs/010-pre-015-user-preset-duplication): playable presets offer Edit; copies of
//   locked-pack presets are listed under "Needs the full library" while the library is not
//   unlocked (tap: the purchase sheet; Information; Remove; R8); an edit dropped because the app
//   closed during its check is reported once (R13). Information shows a copy's origin (US4).
// * PRE-014 (specs/012-pre-014-bulk-preset-export): "Export…" opens the Export Presets sheet;
//   closing it deletes any archive still waiting to be shared.
// * FILE-003 (specs/105-file-003-import-dry-run): a preset archive (`.zip`) picked in "Import
//   Preset…" opens the import preview (PresetArchiveImportView); nothing is stored before Install.
// * PRE-013 (specs/174-pre-013-bulk-import): "Import Folder or Archive…" (BulkImportSection) and its
//   summary sheet (BulkImportSummaryView).
// * PRE-018 (specs/194-pre-018-integrity-scanner): "Check Library" below Quarantine opens LibraryCheckView.
import PresetLibrary
import SwiftUI
import UniformTypeIdentifiers

/// Where the browser's My Presets screens lead.
enum UserPresetRoute: Hashable {
    case list
    case quarantine
    /// PRE-018: the Library Check screen.
    case check
}

struct UserPresetsView: View {
    @Bindable var presets: PresetCoordinator
    @Bindable var userPresets: UserPresetsCoordinator
    let onChoose: (IndexedPreset, PresetScope) -> Void
    /// Closes the whole browser.
    let onDone: () -> Void

    @State private var importing = false
    @State private var exporting = false
    @State private var showingInfo: UserPreset?
    @State private var removing: UserPreset?

    /// `.milk` has no system type; plain data keeps such files selectable. The extension is
    /// checked again when the file is imported. FILE-003: preset archives are `.zip`.
    private static let pickerTypes: [UTType] = [UTType(filenameExtension: "milk"), .zip, .data].compactMap { $0 }

    var body: some View {
        List {
            digestProbe
            if let unavailable = userPresets.unavailableMessage {
                Text(unavailable)
                    .accessibilityIdentifier("userPresetsUnavailable")
            }
            if let notice = userPresets.notice {
                Section {
                    Text(notice).accessibilityIdentifier("userPresetsNotice")
                    Button("Dismiss") { userPresets.dismissNotice() }
                }
            }
            if let notice = userPresets.editNotice {
                Section {
                    Text(notice).accessibilityIdentifier("editNotice")
                    Button("Dismiss") { userPresets.dismissEditNotice() }
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
                        .accessibilityIdentifier("userPresetsEmpty")
                }
                ForEach(playableRows, id: \.record.id) { row in
                    PresetRow(presets: presets, preset: row.indexed, showsPack: false,
                              user: PresetRow.UserActions(info: { showingInfo = row.record }, remove: { removing = row.record }),
                              previewScope: .user) {
                        onChoose(row.indexed, .user)
                    }
                }
            }
            if !userPresets.needsUnlock.isEmpty {
                Section {
                    ForEach(userPresets.needsUnlock) { preset in
                        Button { userPresets.chooseHeld(preset) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).foregroundStyle(Color.primary)   // ACC-004: label colour, not the tint
                                    Text(preset.duplicateOf.map(UserPresetsCoordinator.originText) ?? "")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(UserPresetsCoordinator.heldLabel(name: preset.name))
                        .accessibilityIdentifier("heldPreset:\(preset.name)")
                        .accessibilityAction(named: "Information") { showingInfo = preset }
                        .accessibilityAction(named: "Remove from My Presets") { removing = preset }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { removing = preset } label: { Label("Remove", systemImage: "trash") }.tint(.red)
                            Button { showingInfo = preset } label: { Label("Info", systemImage: "info.circle") }
                        }
                    }
                } header: {
                    Text("Needs the full library")
                } footer: {
                    Text("Copies of presets from the full library play again when it is unlocked. Nothing is deleted.")
                }
                .accessibilityIdentifier("needsUnlockSection")
            }
            if !userPresets.pending.isEmpty {
                Section(UserPresetText.pending) {
                    ForEach(userPresets.pending) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text("It will be checked before it can play.").font(.caption)
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
            // PRE-013: below the presets, so it never pushes a row of My Presets down.
            BulkImportSection(userPresets: userPresets)
            Section {
                NavigationLink(value: UserPresetRoute.quarantine) {
                    HStack {
                        Text("Quarantine")
                        Spacer()
                        Text(userPresets.quarantined.count.formatted())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(UserPresetsCoordinator.quarantineRowLabel(count: userPresets.quarantined.count))
                }
                .accessibilityIdentifier("quarantineLink")
                if userPresets.integrity != nil {   // PRE-018-R11
                    NavigationLink(value: UserPresetRoute.check) { Text("Check Library") }
                        .accessibilityIdentifier("libraryCheckLink")
                }
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
                .disabled(userPresets.isImporting || userPresets.isExporting || userPresets.unavailableMessage != nil || userPresets.bulk.isRunning)
                .accessibilityIdentifier("importPreset")
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    exporting = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(!userPresets.canExport)
                .accessibilityIdentifier("exportPresets")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.pickerTypes, allowsMultipleSelection: false) { result in
            let picked = result.flatMap { urls -> Result<URL, any Error> in
                urls.first.map { .success($0) } ?? .failure(CocoaError(.userCancelled))
            }
            Task { await userPresets.importPicked(picked) }
        }
        .importResultAlert(userPresets)
        .sheet(isPresented: $exporting, onDismiss: { userPresets.finishSharing() }) {
            UserPresetExportView(userPresets: userPresets)
        }
        .sheet(item: archiveReviewBinding) { (review: PresetArchiveReview) in
            PresetArchiveImportView(userPresets: userPresets, review: review)
        }
        .sheet(item: $showingInfo) { preset in UserPresetInfoView(preset: preset) }
        .sheet(isPresented: bulkReportShown) { bulkSummary }
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

    /// FILE-003: the archive preview; dismissing the sheet is Cancel.
    private var archiveReviewBinding: Binding<PresetArchiveReview?> {
        Binding<PresetArchiveReview?>(
            get: { () -> PresetArchiveReview? in userPresets.archiveReview },
            set: { (value: PresetArchiveReview?) in if value == nil, userPresets.archiveReview != nil { userPresets.cancelArchive() } })
    }

    /// PRE-013: the bulk import summary while a report is set; dismissing it clears the report.
    private var bulkReportShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in userPresets.bulk.report != nil },
                      set: { (shown: Bool) in if !shown { userPresets.bulk.dismissReport() } })
    }

    @ViewBuilder
    private var bulkSummary: some View {
        if let report = userPresets.bulk.report {
            BulkImportSummaryView(report: report) { userPresets.bulk.dismissReport() }
        }
    }

    /// DEBUG probe for PresetArchiveImportUITests: the library's snapshot digest.
    @ViewBuilder
    private var digestProbe: some View {
        #if DEBUG
        if userPresets.tracksLibraryDigest {
            Text(userPresets.libraryDigest)
                .font(.caption2)
                .dynamicTypeSize(.xSmall)   // a DEBUG probe: kept small at every text size
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("libraryDigest")
        }
        #endif
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
                    .accessibilityIdentifier(userPresets.quarantined.isEmpty ? "quarantineEmpty" : "quarantineExplanation")
            }
            ForEach(userPresets.quarantined) { preset in
                let reason = preset.quarantine?.message ?? "This preset could not be used."
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.originalFileName)
                        Text(reason)
                            .font(.callout)
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
                    row(preset.duplicateOf == nil ? "Imported" : "Copied", preset.importedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let modified = preset.modifiedAt {
                    Section("Edited") {
                        row("Last saved", modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let origin = preset.duplicateOf {
                    // PRE-015 US4: where the copy came from, and the pack's own statement.
                    Section("Copied from") {
                        Text(UserPresetsCoordinator.originText(origin))
                            .accessibilityIdentifier("presetOrigin")
                        row("Pack's statement", origin.licenseStatement.isEmpty ? "None" : origin.licenseStatement)
                        Text(UserPresetsCoordinator.duplicateRightsText)
                    }
                }
                Section("Author and license") {
                    if preset.duplicateOf != nil {
                        row("Author", preset.author.isEmpty ? "Unknown" : preset.author)
                    } else {
                        row("Author", preset.author.isEmpty ? "Unknown" : "\(preset.author) (from the file name)")
                        Text(PresetLicenseMetadata.rightsText)
                            .accessibilityIdentifier("presetRights")
                    }
                    if preset.license.linesFound.isEmpty {
                        Text(PresetLicenseMetadata.noLicenseText)
                            .accessibilityIdentifier("presetNoLicense")
                    } else {
                        ForEach(Array(preset.license.linesFound.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Found in the file").font(.caption)
                                Text(item.element).font(.callout.monospaced())
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("presetLicenseLine")
                        }
                    }
                }
                Section("Checks") {
                    if preset.warnings.isEmpty {
                        Text("No warnings.")
                    }
                    ForEach(Array(preset.warnings.enumerated()), id: \.offset) { item in
                        Label(item.element.message, systemImage: "exclamationmark.triangle")
                            .accessibilityIdentifier("presetWarning")
                    }
                    Text(preset.provenOnScreen ? "Checked off screen and shown without a problem."
                                               : "Checked off screen. Not shown for long enough yet to count as proven.")
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
            Text(title).font(.caption)
            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}
