// OfflineExportViews.swift — REC-013: the offline export's views (specs/240-rec-013-deterministic-offline-export; R1,
// R8, R10, R11, R15; contract C4).
//
// * `OfflineExportRow`: "Export Video Offline…" under the snapshot rows in Settings › Visual; opens the sheet.
// * `OfflineExportSheet`: Audio (Fixture or Audio File, picked with the system file picker), Seed, Shape, Rate, Export;
//   while rendering "Rendering frame N of M" with a progress bar and Cancel; when finished Save… and Share… (video and
//   checksum sidecar, REC-002's presenters) and Save to Photos (the video). Leaving the foreground stops the export
//   (research REC-013-D9). Done deletes the export. No animation.
import SwiftUI
import UniformTypeIdentifiers

struct OfflineExportRow: View {
    let export: OfflineExportCoordinator
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Video Offline…")
                Text("Renders a repeatable video from an audio file, frame by frame.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Export Video Offline")
        .accessibilityHint("Renders the current visual to a video from an audio file, with a checksum per frame.")
        .accessibilityIdentifier("offlineExportOpen")
        .sheet(isPresented: $open) {
            OfflineExportSheet(export: export)
        }
    }
}

struct OfflineExportSheet: View {
    @Bindable var export: OfflineExportCoordinator
    @State private var importing = false
    @State private var picking = false
    @State private var sharing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                if !export.visualSupported { unsupportedSection }
                audioSection
                optionsSection
                actionSection
                statusSection
            }
            .navigationTitle("Export Video Offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish).accessibilityIdentifier("offlineExportDone")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { (picked: Result<URL, Error>) -> Void in
                if case let .success(url) = picked { export.audioFile = url }
            }
            .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) -> Void in
                if phase == .background { export.sceneLeftForeground() }   // D9
            }
            .background(presenters)
        }
        .accessibilityIdentifier("offlineExportSheet")
        .interactiveDismissDisabled(export.isRendering)
    }

    private var unsupportedSection: some View {
        Section {
            Text(OfflineExportRefusal.unsupportedMessage).accessibilityIdentifier("offlineExportUnsupported")
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            Picker("Audio", selection: $export.audioChoice) {
                ForEach(OfflineExportCoordinator.AudioChoice.allCases) { (c: OfflineExportCoordinator.AudioChoice) in
                    Text(c.title).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .disabled(export.isRendering)
            .accessibilityIdentifier("offlineExportAudio")
            if export.audioChoice == .file { fileRow }
        }
    }

    private var fileRow: some View {
        Button(export.audioFile?.lastPathComponent ?? "Choose File…") { importing = true }
            .disabled(export.isRendering)
            .accessibilityHint("Picks the audio file the video is rendered from.")
            .accessibilityIdentifier("offlineExportChooseFile")
    }

    private var optionsSection: some View {
        Section {
            LabeledContent("Seed") {
                TextField("1", text: $export.seedText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Seed")
                    .accessibilityIdentifier("offlineExportSeed")
            }
            Picker("Shape", selection: $export.shape) {
                ForEach(SnapshotBatchSize.allCases) { (s: SnapshotBatchSize) in
                    Text(s.title + ", " + s.pixels).tag(s)
                }
            }
            .accessibilityIdentifier("offlineExportShape")
            Picker("Rate", selection: $export.rate) {
                ForEach(OfflineExportRate.allCases) { (r: OfflineExportRate) in Text(r.title).tag(r) }
            }
            .accessibilityIdentifier("offlineExportRate")
        } footer: {
            Text("The same visual, audio, seed, shape and rate give the same frames on the same device.")
        }
        .disabled(export.isRendering)
    }

    @ViewBuilder private var actionSection: some View {
        Section {
            if let progress = export.progressText {
                progressRow(progress)
            } else if export.phase == .finished {
                finishedRows
            } else {
                Button("Export") { export.start() }
                    .disabled(!export.visualSupported)
                    .accessibilityIdentifier("offlineExportStart")
            }
        }
    }

    private func progressRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: export.progressFraction) { Text(text) }
                .accessibilityIdentifier("offlineExportProgress")
            Button("Cancel", role: .cancel) { export.cancel() }
                .accessibilityIdentifier("offlineExportCancel")
        }
    }

    @ViewBuilder private var finishedRows: some View {
        Button("Save…") { picking = true }
            .accessibilityHint("Saves the video and its checksum file to a folder you choose.")
            .accessibilityIdentifier("offlineExportSave")
        Button("Share…") { sharing = true }
            .accessibilityIdentifier("offlineExportShare")
        Button("Save to Photos") { export.saveVideoToPhotos() }
            .disabled(export.isSavingToPhotos || export.photos == nil)
            .accessibilityIdentifier("offlineExportPhotos")
    }

    @ViewBuilder private var statusSection: some View {
        if let status = export.status {
            Section {
                Text(status).accessibilityIdentifier("offlineExportStatus")
            }
        }
    }

    private var presenters: some View {
        ZStack {
            BatchExportPicker(files: picking ? export.files : [], onFinish: { () -> Void in picking = false })
            BatchSharePresenter(files: sharing ? export.files : [], onFinish: { () -> Void in sharing = false })
        }
    }

    private func finish() {
        export.done()
        if !export.isRendering { dismiss() }
    }
}
