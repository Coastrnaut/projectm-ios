// StorageUsageView.swift — FILE-009: Settings › Storage. Nine categories and a total, each the space its
// files take on this device (FILE-009-R1, R3), a Refresh button, a busy row while measuring and a note
// when the walk was incomplete (R6). Read-only: clearing caches is FILE-010, erasing data FILE-011 (R7).
// Free space on the device is deliberately not shown (privacy manifest; spec Clarifications).
// FILE-010: Clear Caches… (contracts/cache-cleanup.md C4): a confirmation stating the space to be freed and
// what is kept, then the cleared size and a failure note; the user-data rows never change.
// FILE-008: a note with the space shared photo and video copies save.
// FILE-005: the Backup section (LibraryBackupSection: back up the library, restore from a backup).
// FILE-011: the Erase section and sheet (LibraryEraseSection).
// MED-013: a Missing Media row (MissingMediaView: list, relink by checksum, folder search, replacement).
// REC-010: the Saved recordings row opens Recordings (RecordingLibraryView: play, share, rename, delete).
import LocalPortability
import SwiftUI

struct StorageUsageView: View {
    @State private var model: StorageUsageModel
    /// FILE-005: back up and restore (nil hides the section, e.g. in previews).
    private let libraryBackup: LibraryBackupCoordinator?

    /// MED-013: Missing Media (nil hides the row, e.g. in previews).
    private let missingMedia: MissingMediaCoordinator?
    /// REC-010: Recordings (nil hides the row, e.g. in previews).
    private let recordingLibrary: RecordingLibraryModel?

    init(model: StorageUsageModel? = nil, filesInUse: @escaping @MainActor () -> Set<String> = { () -> Set<String> in [] },
         libraryBackup: LibraryBackupCoordinator? = nil, missingMedia: MissingMediaCoordinator? = nil,
         recordingLibrary: RecordingLibraryModel? = nil) {
        _model = State(initialValue: model ?? StorageUsageModel(locations: StorageLocations.forCurrentLaunch(), filesInUse: filesInUse))
        self.libraryBackup = libraryBackup
        self.missingMedia = missingMedia
        self.recordingLibrary = recordingLibrary
    }

    static let incompleteNote = "Some files could not be counted; sizes may be higher."
    static let keptNote = "Photos, videos, scenes, the show, presets, imported audio, saved recordings and settings are kept."
    static let cleanupFailedNote = "Some files could not be removed."

    /// FILE-008-R11: shown only when shared copies save space.
    static func sharedSavingsNote(_ bytes: Int64) -> String {
        "Shared copies of identical photos and videos save \(format(bytes))."
    }

    /// The confirmation's message (FILE-010-R2).
    static func confirmationMessage(_ plan: CacheCleanupPlan) -> String {
        let size = format(plan.bytesToFree)
        var text = (plan.isComplete ? "Frees \(size). " : "Frees about \(size). ") + keptNote
        if !plan.keptInUse.isEmpty { text += " Files in use are kept." }
        return text
    }

    static func promptTitle(_ prompt: StorageUsageModel.CleanupPrompt?) -> String {
        if case .nothingToClear = prompt { return "Nothing to Clear" }
        return "Clear Caches?"
    }

    static func cleanedNote(_ result: CacheCleanupResult) -> String { "Cleared \(format(result.bytesFreed))." }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func value(_ bytes: Int64?) -> String {
        guard let bytes else { return "Calculating…" }
        return Self.format(bytes)
    }

    /// One row read by VoiceOver as "<title>, <size>".
    private func row(_ title: String, bytes: Int64?, id: String, bold: Bool = false) -> some View {
        let text = value(bytes)
        return HStack {
            Text(title).fontWeight(bold ? .semibold : .regular)
            Spacer()
            // QA-009 (2026-11-14): primary colour; the sizes are the screen's content, and in the secondary grey
            // they "nearly passed" the contrast audit.
            Text(text).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .accessibilityIdentifier(id)
    }

    /// One category row; REC-010: "Saved recordings" opens Settings › Storage › Recordings.
    @ViewBuilder
    private func categoryRow(_ category: StorageCategory, bytes: Int64?) -> some View {
        let id = "storage.\(category.rawValue)"
        if category == .savedRecordings, let recordingLibrary {
            let text = value(bytes)
            NavigationLink { RecordingLibraryView(model: recordingLibrary) } label: {
                HStack {
                    Text(category.title).accessibilityIdentifier(id + ".title")   // audit filters name it (QA-009)
                    Spacer()
                    // Post-merge a11y (2026-11-14): primary colour like the other rows (QA-009); the secondary grey
                    // "nearly passed" the contrast audit.
                    Text(text).monospacedDigit().accessibilityIdentifier(id + ".size")   // the size varies ("Zero KB", "8 KB")
                }
            }
            .accessibilityLabel(category.title)
            .accessibilityValue(text)
            .accessibilityHint("Opens your saved recordings")
            .accessibilityIdentifier(id)
        } else {
            row(category.title, bytes: bytes, id: id)
        }
    }

    var body: some View {
        let report = model.report
        List {
            if model.isMeasuring {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Calculating…").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("storageMeasuring")
                }
            }
            Section {
                ForEach(StorageCategory.allCases, id: \.self) { (category: StorageCategory) in
                    categoryRow(category, bytes: report?.usage(category).spaceUsed)
                }
                row("Total", bytes: report?.total.spaceUsed, id: "storage.total", bold: true)
            } footer: {
                Text("The space this app's own data takes on this device. The app and its bundled presets are not included.")
            }
            if let report, !report.isComplete {
                Section {
                    Text(Self.incompleteNote).accessibilityIdentifier("storageIncomplete")
                }
            }
            cleanupSection
            if let missingMedia {   // MED-013-R11
                Section {
                    NavigationLink("Missing Media") { MissingMediaView(model: missingMedia) }
                        .accessibilityIdentifier("missingMediaLink")
                }
            }
            if model.sharedSavings > 0 {
                Section {
                    Text(Self.sharedSavingsNote(model.sharedSavings)).accessibilityIdentifier("storageSharedSavings")   // FILE-008
                }
            }
            if let libraryBackup { LibraryBackupSection(model: libraryBackup) }   // FILE-005
            #if DEBUG
            if UITestStorageFixture.isEnabled {
                Section {
                    Button("Add Test Recording") { UITestStorageFixture.addRecording() }
                        .accessibilityIdentifier("storageAddFixture")
                }
            }
            #endif
            if let libraryBackup { LibraryEraseSection(model: libraryBackup.erase).id("libraryErase") }   // FILE-011: last (destructive)
        }
        .uitestSettingsSection(repeated: true)   // DEBUG `-uitestSettingsSection libraryErase`: opens at the end (Erase) (owner rule 7)
        .navigationTitle("Storage")
        .libraryBackupPresentation(libraryBackup)   // FILE-005
        .libraryErasePresentation(libraryBackup)   // FILE-011
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { model.refresh() }
                    .disabled(model.isClearing)
                    .accessibilityIdentifier("storageRefresh")
            }
        }
        .alert(Self.promptTitle(model.cleanupPrompt),
               isPresented: Binding(get: { () -> Bool in model.cleanupPrompt != nil },
                                    set: { (shown: Bool) in if !shown { model.dismissCleanup() } }),
               presenting: model.cleanupPrompt) { (prompt: StorageUsageModel.CleanupPrompt) in
            switch prompt {
            case .confirm(let plan):
                Button("Clear", role: .destructive) { model.confirmCleanup(plan) }
                    .accessibilityIdentifier("storageClearConfirm")
                Button("Cancel", role: .cancel) { model.dismissCleanup() }
            case .nothingToClear:
                Button("OK", role: .cancel) { model.dismissCleanup() }
            }
        } message: { (prompt: StorageUsageModel.CleanupPrompt) in
            switch prompt {
            case .confirm(let plan): Text(Self.confirmationMessage(plan))
            case .nothingToClear(let keptInUse): Text(keptInUse ? "The remaining files are in use." : "There are no caches to clear.")
            }
        }
        .onAppear { model.refresh() }
        .onDisappear { model.cancel() }
    }

    /// FILE-010-R1, R6, R9.
    private var cleanupSection: some View {
        Section {
            Button {
                model.prepareCleanup()
            } label: {
                HStack {
                    Text("Clear Caches…")
                    if model.isPlanningCleanup || model.isClearing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!model.canClearCaches)
            .accessibilityIdentifier("storageClearCaches")
            if let result = model.lastCleanup {
                Text(Self.cleanedNote(result)).accessibilityIdentifier("storageCleanupResult")
                if !result.failed.isEmpty {
                    Text(Self.cleanupFailedNote).accessibilityIdentifier("storageCleanupFailed")
                }
            }
        } footer: {
            Text("Removes leftover recordings, share and export copies, and caches the system can rebuild. \(Self.keptNote)")
        }
    }
}
