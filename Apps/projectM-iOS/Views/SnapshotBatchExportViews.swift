// SnapshotBatchExportViews.swift — REC-002: the image batch export's views (specs/234-rec-002-image-batch-export; R1,
// R4, R7, R8; contract B5).
//
// * `SnapshotBatchExportRow`: "Export Images…" under SCN-009's Compare row in Settings › Visual; opens the sheet.
// * `SnapshotBatchExportSheet`: one toggle per snapshot (unusable ones disabled), the size, Export; while rendering
//   "Rendering N of M" with a progress bar and Cancel; when finished Save… (the system folder picker, every file with
//   its name), Share… (the system sheet without Save to Photos and Assign to Contact, REC-012-R7) and Save to Photos
//   (REC-011). Done deletes the batch. No animation.
import SwiftUI
import UIKit

struct SnapshotBatchExportRow: View {
    let export: SnapshotBatchExportCoordinator
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Images…")
                Text(export.hasUsableSnapshot ? "Renders each snapshot to its own PNG file." : "Save a snapshot first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!export.hasUsableSnapshot)
        .accessibilityLabel("Export Images")
        .accessibilityHint(export.hasUsableSnapshot ? "Renders the chosen snapshots to image files." : "Save a snapshot first.")
        .accessibilityIdentifier("snapshotBatchOpen")
        .sheet(isPresented: $open) {
            SnapshotBatchExportSheet(export: export)
        }
    }
}

struct SnapshotBatchExportSheet: View {
    @Bindable var export: SnapshotBatchExportCoordinator
    @State private var picking = false
    @State private var sharing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !export.visualSupported { unsupportedSection }
                snapshotSection
                sizeSection
                actionSection
                statusSection
            }
            .navigationTitle("Export Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish).accessibilityIdentifier("snapshotBatchDone")
                }
            }
            .onAppear { export.prepare() }
            .background(presenters)
        }
        .accessibilityIdentifier("snapshotBatchSheet")
        .interactiveDismissDisabled(export.isRendering)
    }

    private var unsupportedSection: some View {
        Section {
            Text(SnapshotBatchRefusal.unsupportedMessage).accessibilityIdentifier("snapshotBatchUnsupported")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshots") {
            ForEach(export.rows) { (row: SceneSnapshotRow) in
                Toggle(row.name, isOn: binding(row.index))
                    .disabled(!row.isUsable || export.isRendering)
                    .accessibilityValue(row.isUsable ? (export.selection.contains(row.index) ? "Selected" : "Not selected") : "Can't be used")
                    .accessibilityIdentifier("snapshotBatchToggle.\(row.index)")
            }
        }
    }

    private var sizeSection: some View {
        Section("Size") {
            Picker("Size", selection: $export.size) {
                ForEach(SnapshotBatchSize.allCases) { (s: SnapshotBatchSize) in
                    Text(s.title + ", " + s.pixels).tag(s)
                }
            }
            .disabled(export.isRendering)
            .accessibilityIdentifier("snapshotBatchSize")
        }
    }

    @ViewBuilder private var actionSection: some View {
        Section {
            if let progress = export.progressText {
                progressRow(progress)
            } else if export.phase == .finished {
                finishedRows
            } else {
                Button("Export \(export.selection.count == 1 ? "1 Image" : "\(export.selection.count) Images")") { export.start() }
                    .disabled(export.selection.isEmpty || !export.visualSupported)
                    .accessibilityIdentifier("snapshotBatchExport")
            }
        }
    }

    private func progressRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progressFraction) { Text(text) }
                .accessibilityIdentifier("snapshotBatchProgress")
            Button("Cancel", role: .cancel) { export.cancel() }
                .accessibilityIdentifier("snapshotBatchCancel")
        }
    }

    @ViewBuilder private var finishedRows: some View {
        Button("Save…") { picking = true }
            .accessibilityHint("Saves every image to a folder you choose.")
            .accessibilityIdentifier("snapshotBatchSave")
        Button("Share…") { sharing = true }
            .accessibilityIdentifier("snapshotBatchShare")
        Button("Save to Photos") { export.saveAllToPhotos() }
            .disabled(export.isSavingToPhotos || export.photos == nil)
            .accessibilityIdentifier("snapshotBatchPhotos")
    }

    @ViewBuilder private var statusSection: some View {
        if export.status != nil || showsProbe {
            Section {
                if let status = export.status { Text(status).accessibilityIdentifier("snapshotBatchStatus") }
                #if DEBUG
                Text(export.probe.isEmpty ? "none" : export.probe)
                    .font(.caption2)
                    .accessibilityIdentifier("snapshotBatchProbe")
                #endif
            }
        }
    }

    private var showsProbe: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var presenters: some View {
        ZStack {
            BatchExportPicker(files: picking ? export.files : [], onFinish: { () -> Void in picking = false })
            BatchSharePresenter(files: sharing ? export.files : [], onFinish: { () -> Void in sharing = false })
        }
    }

    private var progressFraction: Double {
        guard case let .rendering(done, total) = export.phase, total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    private func binding(_ index: Int) -> Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in export.selection.contains(index) },
                      set: { (on: Bool) -> Void in
                          if on { export.selection.insert(index) } else { export.selection.remove(index) }
                      })
    }

    private func finish() {
        export.done()
        if !export.isRendering { dismiss() }
    }
}

/// Save…: the system folder picker exporting copies of every file with its own name (REC-002-D8).
private struct BatchExportPicker: UIViewControllerRepresentable {
    let files: [URL]
    let onFinish: @MainActor () -> Void

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var presented = false
        var onFinish: @MainActor () -> Void = { () -> Void in }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish() }

        private func finish() {
            presented = false
            onFinish()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onFinish = onFinish
        guard !files.isEmpty, !context.coordinator.presented else { return }
        context.coordinator.presented = true
        let picker = UIDocumentPickerViewController(forExporting: files, asCopy: true)
        picker.delegate = context.coordinator
        Task { @MainActor in controller.present(picker, animated: true) }
    }
}

/// Share…: the system share sheet with every file, without Save to Photos and Assign to Contact (REC-012-R7).
private struct BatchSharePresenter: UIViewControllerRepresentable {
    let files: [URL]
    let onFinish: @MainActor () -> Void

    @MainActor
    final class Coordinator {
        var presented = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard !files.isEmpty, !context.coordinator.presented else { return }
        context.coordinator.presented = true
        let activity = UIActivityViewController(activityItems: files, applicationActivities: nil)
        activity.excludedActivityTypes = ShareFileStore.excludedActivityTypes
        let coordinator = context.coordinator
        let finish = onFinish
        activity.completionWithItemsHandler = { (_: UIActivity.ActivityType?, _: Bool, _: [Any]?, _: (any Error)?) in
            Task { @MainActor in
                coordinator.presented = false
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
