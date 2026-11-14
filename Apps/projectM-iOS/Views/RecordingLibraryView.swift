// RecordingLibraryView.swift — REC-010 Settings › Storage › Recordings (contract C4-C6, C8; REC-010-R2 to R6, R9).
//
// * A summary ("3 recordings, 12 MB"), then one row per saved recording, newest first: thumbnail, name, duration,
//   size, date, resolution, frame rate and codec; an unreadable file reads "Incomplete" and offers Delete only.
// * Each row's facts are one VoiceOver element with Play, Share, Rename and Delete as actions too; the visible
//   buttons below it stay reachable on their own.
// * Delete asks first ("Delete Recording?"); the row disappears in the same update as the confirmation.
// * Play: an AVKit player for the local file. Share…: REC-012's presenter with the file itself (Save to Photos and
//   Assign to Contact excluded). Rename: an alert with the name without its extension.
import AVKit
import SwiftUI

struct RecordingLibraryView: View {
    let model: RecordingLibraryModel
    @State private var renaming: RecordingLibraryItem?
    @State private var newName = ""
    @State private var renameError: String?
    @State private var shareRequest: CaptureShareCoordinator.Request?
    @State private var player: AVPlayer?

    var body: some View {
        List {
            summarySection
            if !model.items.isEmpty { rowsSection }
            if let message = model.message {
                Section { Text(message).accessibilityIdentifier("recordingLibraryMessage") }
            }
        }
        .navigationTitle("Recordings")
        .onAppear { model.refresh() }
        .alert("Delete Recording?", isPresented: deleteBinding, presenting: model.pendingDelete) { (_: RecordingLibraryItem) in
            Button("Delete", role: .destructive) { model.confirmDelete() }
                .accessibilityIdentifier("recordingLibraryConfirmDelete")
            Button("Cancel", role: .cancel) { model.cancelDelete() }
                .accessibilityIdentifier("recordingLibraryCancelDelete")
        } message: { (item: RecordingLibraryItem) in
            Text(RecordingLibraryModel.deleteMessage(item))
        }
        .alert("Rename Recording", isPresented: renameBinding, presenting: renaming) { (item: RecordingLibraryItem) in
            TextField("Name", text: $newName)
                .accessibilityIdentifier("recordingLibraryRenameField")
            Button("Rename") { renameError = model.rename(item, to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: { (_: RecordingLibraryItem) in
            Text(renameError ?? "The file keeps its extension.")
        }
        .sheet(isPresented: playerBinding) { playerSheet }
        .background {
            ActivitySharePresenter(request: shareRequest, kind: .recording) { (_: ShareOutcome) in shareRequest = nil }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        let text = model.summaryText
        return Section {
            Text(text)
                .accessibilityLabel(text)
                .accessibilityIdentifier("recordingLibrarySummary")
        } footer: {
            Text("Recordings you keep after recording. They stay on this device until you delete them.")
        }
    }

    private var rowsSection: some View {
        Section {
            ForEach(model.items) { (item: RecordingLibraryItem) in
                RecordingLibraryRow(item: item, actions: actions(for: item))
            }
        }
    }

    private func actions(for item: RecordingLibraryItem) -> RecordingLibraryRow.Actions {
        RecordingLibraryRow.Actions(
            play: { () -> Void in player = AVPlayer(url: item.file.url) },
            share: { () -> Void in shareRequest = CaptureShareCoordinator.Request(id: UUID(), kind: .recording, url: item.file.url) },
            rename: { () -> Void in
                newName = RecordingLibraryStore.stem(of: item.file.name)
                renameError = nil
                renaming = item
            },
            delete: { () -> Void in model.requestDelete(item) })
    }

    // MARK: - Presentation

    private var deleteBinding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in model.pendingDelete != nil },
                      set: { (shown: Bool) in if !shown { model.cancelDelete() } })
    }

    private var renameBinding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in renaming != nil },
                      set: { (shown: Bool) in if !shown { renaming = nil } })
    }

    private var playerBinding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in player != nil },
                      set: { (shown: Bool) in if !shown { player?.pause(); player = nil } })
    }

    @ViewBuilder
    private var playerSheet: some View {
        if let player {
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .accessibilityIdentifier("recordingLibraryPlayer")
        }
    }
}

/// One saved recording.
struct RecordingLibraryRow: View {
    struct Actions {
        let play: () -> Void
        let share: () -> Void
        let rename: () -> Void
        let delete: () -> Void
    }

    let item: RecordingLibraryItem
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summary
            buttons
        }
    }

    /// The row's one VoiceOver element: its facts, with the actions as accessibility actions too.
    private var summary: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(RecordingLibraryStore.stem(of: item.file.name)).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(detailText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecordingLibraryModel.accessibilityLabel(item))
        .accessibilityIdentifier("recordingLibraryRow")
        .accessibilityActions { accessibilityActionList }
    }

    private var detailText: String {
        let size = RecordingLibraryModel.format(item.file.bytes)
        let date = RecordingLibraryModel.dateText(item.file.date)
        switch item.state {
        case .incomplete: return "Incomplete · \(size) · \(date)"
        case .loading: return "\(size) · \(date)"
        case let .ready(f):
            let first: String = "\(f.durationText) · \(size) · \(date)"
            return first + "\n\(f.resolutionText) · \(f.frameRateText) · \(f.codecText)"
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.2))
                .frame(width: 64, height: 64)
                .overlay { Image(systemName: item.isIncomplete ? "exclamationmark.triangle" : "film").foregroundStyle(.secondary) }
        }
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            if !item.isIncomplete && item.facts != nil {
                Button("Play", action: actions.play).accessibilityIdentifier("recordingLibraryPlay")
                Button("Share…", action: actions.share).accessibilityIdentifier("recordingLibraryShare")
                Button("Rename", action: actions.rename).accessibilityIdentifier("recordingLibraryRename")
            }
            Button("Delete", role: .destructive, action: actions.delete).accessibilityIdentifier("recordingLibraryDelete")
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private var accessibilityActionList: some View {
        if item.facts != nil {
            Button("Play", action: actions.play)
            Button("Share", action: actions.share)
            Button("Rename", action: actions.rename)
        }
        Button("Delete", action: actions.delete)
    }
}
