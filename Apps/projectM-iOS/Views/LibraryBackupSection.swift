// LibraryBackupSection.swift — FILE-005 (contract C7; FILE-005-R4-R6, R12): Settings › Storage › Backup.
// Back Up Library… (then the system file mover), Restore from Backup… (the system file picker, then the
// preview sheet), the pending restore with Cancel Restore, and the last result. Standard List rows and
// text that wraps, so Dynamic Type and VoiceOver apply; nothing animates. Small bodies (CI's Xcode 26).
import LibraryBackup
import SwiftUI
import UniformTypeIdentifiers

struct LibraryBackupSection: View {
    @Bindable var model: LibraryBackupCoordinator

    var body: some View {
        Section {
            actions
            FolderBackupRows(model: model.folder)   // FILE-006
            if model.isRestorePending { pendingRows }
            if let message = model.message {
                Text(message).font(.footnote).accessibilityIdentifier("libraryBackupMessage")
            }
            #if DEBUG
            if !model.recordsProbe.isEmpty {
                Text(model.recordsProbe).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("libraryRecordsProbe")
            }
            #endif
        } header: {
            Text("Backup")
        } footer: {
            Text(LibraryBackupCoordinator.footer)
        }
        .onAppear { model.refresh() }
    }

    private var actions: some View {
        Group {
            Button("Back Up Library…") { model.backUp() }
                .disabled(model.isWorking)
                .accessibilityIdentifier("libraryBackupButton")
            Button("Restore from Backup…") { if model.restoreTapped() { model.showPicker = true } }
                .disabled(model.isWorking || model.isRestorePending || model.erase.pending != nil)   // FILE-011: not while an erase waits
                .accessibilityIdentifier("libraryRestoreButton")
            if model.isWorking {
                ProgressView().accessibilityLabel("Working")
            }
        }
    }

    private var pendingRows: some View {
        Group {
            Text(LibraryBackupCoordinator.pendingText).accessibilityIdentifier("libraryRestorePending")
            Button("Cancel Restore", role: .destructive) { model.cancelRestore() }
                .accessibilityIdentifier("libraryRestoreCancel")
        }
    }

}

/// The picker, the file mover and the preview sheet, attached to the screen's List (presentations on
/// a lazily built section row are unreliable).
struct LibraryBackupPresentation: ViewModifier {
    @Bindable var model: LibraryBackupCoordinator

    struct PreviewItem: Identifiable {
        let preview: LibraryRestorePreview
        var id: String { preview.plan.backupDigest + preview.plan.choice.rawValue }
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $model.showPicker, allowedContentTypes: [.data], allowsMultipleSelection: false) {
                (result: Result<[URL], any Error>) in
                if case let .success(urls) = result, let url = urls.first { model.previewRestore(at: url) }
            }
            .fileMover(isPresented: $model.showMover, file: model.backupFile) { (result: Result<URL, any Error>) in
                model.moverFinished(result)
            } onCancellation: {
                model.moverCancelled()
            }
            .background { FolderBackupPicker(model: model.folder) }   // FILE-006: its own view (one importer per view)
            .sheet(item: Binding(get: { model.preview.map(PreviewItem.init) },
                                 set: { (item: PreviewItem?) in if item == nil { model.cancelPreview() } })) { (item: PreviewItem) in
                LibraryRestorePreviewView(model: model, preview: item.preview)
            }
    }
}

extension View {
    /// FILE-005: the Backup section's presentations (nil: none).
    @ViewBuilder
    func libraryBackupPresentation(_ model: LibraryBackupCoordinator?) -> some View {
        if let model { modifier(LibraryBackupPresentation(model: model)) } else { self }
    }
}

/// The dry run: what the backup holds against this library, "Apply to all", and the request.
struct LibraryRestorePreviewView: View {
    let model: LibraryBackupCoordinator
    let preview: LibraryRestorePreview

    var body: some View {
        NavigationStack {
            List {
                summarySection
                choiceSection
                if let refusal = preview.plan.refusal {
                    Section { Text(refusal.message).accessibilityIdentifier("libraryRestoreRefusal") }
                }
            }
            .navigationTitle("Restore from Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    private var summarySection: some View {
        Section {
            ForEach(preview.lines, id: \.title) { (line: (title: String, text: String)) in
                LabeledContent(line.title, value: line.text)
            }
        } header: {
            Text("In this backup")
        } footer: {
            Text("Made with version \(preview.manifest.appVersion). The restore happens the next time the app opens. Restored presets are checked before they can play.")
        }
    }

    private var choiceSection: some View {
        Section {
            Picker("Apply to all", selection: Binding(get: { preview.plan.choice }, set: { (choice: LibraryRestoreChoice) in model.setChoice(choice) })) {
                ForEach(LibraryRestoreChoice.allCases, id: \.self) { (choice: LibraryRestoreChoice) in
                    Text(LibraryBackupCoordinator.choiceTitle(choice)).tag(choice)
                }
            }
            .accessibilityIdentifier("libraryRestoreChoice")
        } footer: {
            Text(LibraryBackupCoordinator.choiceExplanation(preview.plan.choice))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { model.cancelPreview() }.accessibilityIdentifier("libraryRestoreDismiss")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Restore at Next Launch") { model.requestRestore() }
                .disabled(!preview.plan.canRestore)
                .accessibilityIdentifier("libraryRestoreConfirm")
        }
    }
}

/// FILE-006 (FILE-006-R1, R9): Back Up to Folder…, Restore Media from Folder…, the pending media restore
/// and the last folder result. Standard rows, wrapping text, nothing animates.
struct FolderBackupRows: View {
    @Bindable var model: FolderBackupCoordinator

    var body: some View {
        Group {
            Button("Back Up to Folder…") { model.backUpTapped() }
                .disabled(model.isWorking)
                .accessibilityIdentifier("folderBackupButton")
            Button("Restore Media from Folder…") { model.restoreTapped() }
                .disabled(model.isWorking || model.isRestorePending)
                .accessibilityIdentifier("folderRestoreButton")
            if model.isWorking {
                ProgressView().accessibilityLabel("Working")
            }
            if model.isRestorePending { pendingRows }
            if let message = model.message {
                Text(message).font(.footnote).accessibilityIdentifier("folderBackupMessage")
            }
        }
    }

    private var pendingRows: some View {
        Group {
            Text(FolderBackupCoordinator.pendingText).accessibilityIdentifier("folderRestorePending")
            Button("Cancel Media Restore", role: .destructive) { model.cancelRestore() }
                .accessibilityIdentifier("folderRestoreCancel")
        }
    }
}

/// The system folder picker for both folder actions (a view of its own: one `fileImporter` per view).
struct FolderBackupPicker: View {
    @Bindable var model: FolderBackupCoordinator

    var body: some View {
        Color.clear
            .fileImporter(isPresented: $model.showPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) {
                (result: Result<[URL], any Error>) in
                if case let .success(urls) = result, let url = urls.first { model.picked(url, for: model.pickerPurpose) }
            }
    }
}
