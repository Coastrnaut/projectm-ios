// OutputProfileRows.swift — OUT-014 (contract C3): Settings › External Display's "Export output profile…" and
// "Import output profile…" rows, the status line, the file mover, the file picker (any data file: the content decides)
// and the different-class confirmation. Standard buttons and wrapping text (Dynamic Type, VoiceOver); nothing animates.
// Small bodies (CI's Xcode 26 type-check budget).
import SwiftUI
import UniformTypeIdentifiers

struct OutputProfileRows: View {
    var setting: ExternalOutputSetting
    @Bindable var profiles: OutputProfileCoordinator

    init(setting: ExternalOutputSetting) {
        self.setting = setting
        profiles = setting.profiles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            exportButton
            importButton
            messageText
        }
        .modifier(OutputProfileFilePresentation(setting: setting, profiles: profiles))
    }

    private var exportButton: some View {
        Button(OutputProfileCoordinator.exportTitle) { profiles.prepareExport(setting) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("outputProfileExport")
    }

    private var importButton: some View {
        Button(OutputProfileCoordinator.importTitle) { profiles.beginImport(setting) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("outputProfileImport")
    }

    @ViewBuilder private var messageText: some View {
        if let message = profiles.message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("outputProfileMessage")
        } else {
            Text(OutputProfileCoordinator.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Export (file mover), Import (file picker) and the different-class warning (OUT-014-R4, R5, R8).
private struct OutputProfileFilePresentation: ViewModifier {
    var setting: ExternalOutputSetting
    @Bindable var profiles: OutputProfileCoordinator

    private var warningShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in profiles.pending != nil },
                      set: { (shown: Bool) -> Void in if !shown { profiles.cancelPending() } })
    }

    func body(content: Content) -> some View {
        content
            .fileMover(isPresented: $profiles.showMover, file: profiles.exportFile) { (result: Result<URL, any Error>) in
                profiles.exportFinished(result)
            } onCancellation: {
                profiles.exportCancelled()
            }
            .fileImporter(isPresented: $profiles.showImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) {
                (result: Result<[URL], any Error>) in
                if case let .success(urls) = result, let url = urls.first { profiles.importFile(at: url, into: setting) }
            }
            .confirmationDialog(OutputProfileCoordinator.warningTitle, isPresented: warningShown, titleVisibility: .visible) {
                Button("Apply Anyway") { profiles.applyPending(into: setting) }
                    .accessibilityIdentifier("outputProfileApplyAnyway")
                Button("Cancel", role: .cancel) { profiles.cancelPending() }
            } message: {
                Text(profiles.pending?.text ?? "")
            }
    }
}
