// MissingMediaView.swift — MED-013 (spec MED-013-R2, R5, R6, R11; contract L6): Settings › Storage › Missing
// Media and the visualizer's "Missing media" placeholder tile.
//
// * The screen lists each missing photo or video (kind and short identifier, "Used by N scenes and M
//   cues", "checksum unknown" when only a replacement can relink it) with Relink… (a file picker of the
//   item's kind) as a button and a VoiceOver action; Find Missing Media in Folder… (a folder picker) is
//   one button for all rows. One Files importer serves both (its content types follow the request).
// * Results are shown under the list and announced on the library lane by the coordinator (ACC-004).
// * The tile: a small accessibility element ("Missing media", the scene name) with Relink…, which opens
//   the screen in a sheet. It never covers the safety controls.
import SwiftUI
import UniformTypeIdentifiers

struct MissingMediaView: View {
    @Bindable var model: MissingMediaCoordinator
    @State private var request: PickerRequest?

    /// What the Files importer was opened for.
    private enum PickerRequest: Equatable {
        case folder
        case replace(MissingMediaItem)

        var types: [UTType] {
            switch self {
            case .folder: [.folder]
            case let .replace(item): item.store == .photos ? [.image] : [.movie, .quickTimeMovie, .mpeg4Movie]
            }
        }
    }

    var body: some View {
        List {
            itemsSection
            findSection
            if let text = model.resultText {
                Section {
                    Text(text).accessibilityIdentifier("missingMediaResult")
                }
            }
        }
        .navigationTitle("Missing Media")
        .fileImporter(isPresented: importerShown, allowedContentTypes: request?.types ?? [.folder]) { (result: Result<URL, any Error>) in
            let current = request
            request = nil
            Task { await handle(current, result) }
        }
        .onAppear { model.refresh() }
    }

    private var importerShown: Binding<Bool> {
        Binding(get: { () -> Bool in request != nil }, set: { (shown: Bool) in if !shown { request = nil } })
    }

    private func handle(_ request: PickerRequest?, _ result: Result<URL, any Error>) async {
        switch request {
        case .folder: await model.folderPicked(result)
        case let .replace(item): await model.replacementPicked(item, result)
        case nil: break
        }
    }

    @ViewBuilder private var itemsSection: some View {
        Section {
            if model.items.isEmpty {
                Text(MissingMediaCoordinator.emptyText)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("missingMediaEmpty")
            } else {
                ForEach(model.items) { (item: MissingMediaItem) in row(item) }
            }
        } footer: {
            Text("Photos and videos your saved scenes use that are no longer stored on this device.")
        }
    }

    private func row(_ item: MissingMediaItem) -> some View {
        HStack {
            Image(systemName: item.store == .photos ? "photo" : "film").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.usageText).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.kindTitle)
            .accessibilityValue(item.usageText)
            .accessibilityIdentifier("missingMedia.\(item.storeID.uuidString)")
            .accessibilityAction(named: "Relink") { request = .replace(item) }
            Spacer()
            Button("Relink…") { request = .replace(item) }
                .buttonStyle(.borderless)
                .disabled(model.isWorking)
                .accessibilityLabel("Relink \(item.title)")
                .accessibilityIdentifier("missingMediaRelink.\(item.storeID.uuidString)")
        }
    }

    private var findSection: some View {
        Section {
            Button("Find Missing Media in Folder…") { startFind() }
                .disabled(!model.canFindInFolder)
                .accessibilityIdentifier("missingMediaFind")
            if model.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(MissingMediaCoordinator.busyText).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text("Looks for the same files, byte for byte, in a folder you pick, such as a backup folder. The folder is only read.")
        }
    }

    private func startFind() {
        #if DEBUG
        if model.findInFixtureFolderIfSet() { return }
        #endif
        request = .folder
    }
}

/// MED-013-R2: shown while the applied show scene's media is missing.
struct MissingMediaTile: View {
    @Bindable var model: MissingMediaCoordinator

    /// The tile stays while its sheet is open, so a relink that clears the placeholder does not close the screen.
    private var valueText: String { model.placeholder?.valueText ?? "Relinked" }

    var body: some View {
        if model.placeholder != nil || model.showsScreenFromPlaceholder {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.square.dashed").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missing media").font(.footnote.bold())
                    Text(valueText).font(.footnote)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Missing media")
                .accessibilityValue(valueText)
                .accessibilityIdentifier("missingMediaPlaceholder")
                Button("Relink…") { model.showsScreenFromPlaceholder = true }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("missingMediaPlaceholderRelink")
            }
            .padding(10)
            .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
            .sheet(isPresented: $model.showsScreenFromPlaceholder) { screen }
        }
    }

    private var screen: some View {
        NavigationStack {
            MissingMediaView(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { model.showsScreenFromPlaceholder = false }
                            .accessibilityIdentifier("missingMediaDone")
                    }
                }
        }
    }
}
