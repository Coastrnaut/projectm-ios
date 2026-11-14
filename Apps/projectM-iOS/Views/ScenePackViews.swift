// ScenePackViews.swift — Scene Folders' scene pack controls (SCN-014-R5, R9; contract
// specs/187-scn-014-dependency-pack/contracts/scene-pack.md P5).
//
// * `ScenePackSection` (top level of Scene Folders): "Import Scene…" (file picker for `.pmscene` packs,
//   research SCN-014-D7), the last result and the preview sheet. Its own view, so the picker and sheet do
//   not crowd `SceneFoldersView.body`.
// * `scenePackShare(_:visible:)`: the share sheet for an exported pack, from the folder level on screen.
// * `ScenePackPreviewSheet`: what Import would do (scene, media counts, size, show conflict, SCN-012 entries,
//   licences) with Import and Cancel. Rows wrap at every text size; each is one accessibility element.
import SceneArchive
import SceneFormat
import SwiftUI
import UniformTypeIdentifiers

enum ScenePackType {
    /// FILE-001's archive type, declared in the app's `UTExportedTypeDeclarations`.
    static let archive = UTType(exportedAs: SceneArchiveFormat.typeIdentifier, conformingTo: .data)
}

struct ScenePackSection: View {
    @Bindable var packs: ScenePackCoordinator

    var body: some View {
        Section {
            importButton
            if let status = packs.status {
                Text(status)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scenePackStatus")
            }
        } footer: {
            Text("A scene pack holds one scene with the photos, slides, logo and video you imported. It never needs the internet.")
        }
    }

    private var importButton: some View {
        Button {
            packs.startImport()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "square.and.arrow.down").accessibilityHidden(true)
                Text("Import Scene…").fixedSize(horizontal: false, vertical: true)
                if packs.isBusy {
                    Spacer(minLength: 0)
                    ProgressView()
                }
            }
        }
        .disabled(packs.isBusy)
        .accessibilityIdentifier("scenePackImportRow")
        .fileImporter(isPresented: $packs.showPicker, allowedContentTypes: [ScenePackType.archive], allowsMultipleSelection: false) {
            (result: Result<[URL], any Error>) in
            if case let .success(urls) = result, let url = urls.first { packs.picked(url) }
        }
        .sheet(item: previewBinding) { (item: PreviewItem) in
            ScenePackPreviewSheet(packs: packs, preview: item.preview)
        }
    }

    private struct PreviewItem: Identifiable {
        let preview: ScenePackPreview
        var id: String { preview.archiveSHA256 + preview.sceneName }
    }

    private var previewBinding: Binding<PreviewItem?> {
        Binding(get: { () -> PreviewItem? in packs.preview.map(PreviewItem.init(preview:)) },
                set: { (item: PreviewItem?) in if item == nil { packs.cancelImport() } })
    }
}

extension View {
    /// The share sheet for an exported pack, presented only by the Scene Folders level on screen.
    func scenePackShare(_ packs: ScenePackCoordinator?, visible: Bool) -> some View {
        background(ShareSheetPresenter(url: visible ? packs?.shareURL : nil) { packs?.shareFinished() })
    }
}

struct ScenePackPreviewSheet: View {
    let packs: ScenePackCoordinator
    let preview: ScenePackPreview

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !preview.repairEntries.isEmpty { repairSection }
            }
            .navigationTitle("Import Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .accessibilityIdentifier("scenePackPreview")
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { packs.cancelImport() }.accessibilityIdentifier("scenePackCancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Import") { packs.confirmImport() }
                .disabled(!preview.canImport || packs.isBusy)
                .accessibilityIdentifier("scenePackImport")
        }
    }

    private var summarySection: some View {
        Section {
            row("Result", outcomeText, identifier: "scenePackOutcome")
            if preview.document != nil {
                row("Scene", preview.sceneName, identifier: "scenePackSceneName")
                row("Media", mediaText, identifier: "scenePackMedia")
                row("Size", ByteCountFormatter.string(fromByteCount: Int64(preview.totalBytes), countStyle: .file), identifier: "scenePackSize")
                row("Licences", "None needed: only media you imported", identifier: "scenePackLicences")
            }
        } footer: {
            Text("Importing adds the scene and one cue. Nothing is shown until you go to the cue.")
        }
    }

    private var repairSection: some View {
        Section("To review after importing") {
            ForEach(Array(preview.repairEntries.enumerated()), id: \.offset) { (pair: (offset: Int, element: SceneRepairReport.Entry)) in
                row(pair.element.item, pair.element.problem, identifier: "scenePackRepair.\(pair.offset)")
            }
        }
    }

    private func row(_ title: String, _ value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var outcomeText: String {
        switch preview.status {
        case let .refused(message): return message
        case .new: return "Adds the scene and a cue."
        case let .copy(name): return "This scene is already in the show; adds a copy, \"\(name)\", and a cue."
        case .identical: return ScenePackCoordinator.alreadyInShowMessage(preview.sceneName)
        }
    }

    private var mediaText: String {
        var parts: [String] = []
        if preview.photoCount > 0 { parts.append(preview.photoCount == 1 ? "1 photo" : "\(preview.photoCount) photos") }
        if preview.slideCount > 0 { parts.append(preview.slideCount == 1 ? "1 slide" : "\(preview.slideCount) slides") }
        if preview.logoCount > 0 { parts.append("1 logo") }
        if preview.videoCount > 0 { parts.append("1 video") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}
