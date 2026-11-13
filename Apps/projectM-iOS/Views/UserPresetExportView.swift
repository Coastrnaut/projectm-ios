// UserPresetExportView.swift — Export Presets: choose user presets, write one archive, share it
// (roadmap PRE-014, specs/012-pre-014-bulk-preset-export; PRE-014-R1, R3-R5, R17;
// contracts/preset-archive.md §5).
//
// * Every exportable preset is listed and selected; Select All / Select None; the count; a footer
//   saying what cannot be exported and why (ADR-0008: copies of full-library presets stay here).
// * Export writes the archive, shows and announces the summary, then opens the system share
//   sheet with that file only. Nothing leaves the device unless the user completes a share.
// * The share sheet's completion (shared or cancelled) deletes the file.
// * Labels wrap at every text size; rows are single accessibility elements with their state.
import PresetLibrary
import SwiftUI
import UIKit

struct UserPresetExportView: View {
    @Bindable var userPresets: UserPresetsCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var prepared = false

    private var exportable: [UserPreset] { userPresets.exportPlan.exportable }

    var body: some View {
        NavigationStack {
            List {
                if let summary = userPresets.exportSummary {
                    Section {
                        Label(summary, systemImage: "checkmark.circle")
                            .accessibilityIdentifier("exportSummary")
                    }
                }
                if let error = userPresets.exportError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .accessibilityIdentifier("exportError")
                    }
                }
                if prepared && exportable.isEmpty {
                    Section {
                        Text(UserPresetText.exportNothing)
                            .accessibilityIdentifier("exportNothing")
                    } footer: {
                        exclusionsFooter
                    }
                } else if !exportable.isEmpty {
                    Section {
                        Button("Select All") { selected = Set(exportable.map(\.id)) }
                            .disabled(selected.count == exportable.count)
                            .accessibilityIdentifier("exportSelectAll")
                        Button("Select None") { selected = [] }
                            .disabled(selected.isEmpty)
                            .accessibilityIdentifier("exportSelectNone")
                    }
                    Section {
                        ForEach(exportable) { preset in row(preset) }
                    } header: {
                        Text(UserPresetsCoordinator.exportCountText(selected: selected.count, of: exportable.count))
                            .accessibilityIdentifier("exportCount")
                    } footer: {
                        exclusionsFooter
                    }
                }
            }
            .navigationTitle(UserPresetText.exportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(userPresets.exportSummary == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("exportDone")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let ids = exportable.map(\.id).filter(selected.contains)
                        Task { _ = await userPresets.export(ids: ids) }
                    } label: {
                        if userPresets.isExporting { ProgressView() } else { Text("Export") }
                    }
                    .disabled(selected.isEmpty || !userPresets.canExport)
                    .accessibilityLabel("Export")
                    .accessibilityIdentifier("exportConfirm")
                }
            }
        }
        .accessibilityIdentifier("presetExportSheet")
        .background(ShareSheetPresenter(url: userPresets.exportFile) { userPresets.finishSharing() })
        .task {
            await userPresets.prepareExport()
            selected = Set(userPresets.exportPlan.exportable.map(\.id))
            prepared = true
        }
    }

    /// What cannot be exported and why, then what Export does. Below the rows, so the list is
    /// reachable first at large text sizes.
    private var exclusionsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = userPresets.exportExclusionText {
                Text(text).accessibilityIdentifier("exportExclusions")
            }
            Text(UserPresetText.exportExplanation)
        }
    }

    private func row(_ preset: UserPreset) -> some View {
        let isSelected = selected.contains(preset.id)
        return Button {
            if isSelected { selected.remove(preset.id) } else { selected.insert(preset.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).foregroundStyle(.primary)
                    if let origin = preset.duplicateOf {
                        Text(UserPresetsCoordinator.originText(origin))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UserPresetsCoordinator.exportRowLabel(name: preset.name, selected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("exportRow:\(preset.name)")
    }
}

/// Presents the system share sheet for `url` from inside the SwiftUI hierarchy and reports when
/// it closes, whether the user shared the file or cancelled (research D6).
struct ShareSheetPresenter: UIViewControllerRepresentable {
    let url: URL?
    let onFinish: @MainActor () -> Void

    @MainActor
    final class Coordinator {
        var presented: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let url, context.coordinator.presented != url else { return }
        context.coordinator.presented = url
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let coordinator = context.coordinator
        let finish = onFinish
        activity.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                coordinator.presented = nil
                finish()
            }
        }
        if let popover = activity.popoverPresentationController {   // iPad
            popover.sourceView = controller.view
            popover.sourceRect = controller.view.bounds
        }
        Task { @MainActor in controller.present(activity, animated: true) }
    }
}
