// ImportedAudioSection.swift — the "Your Audio" section of the source chooser (AUD-001-T15;
// AUD-001-R1, R9, R10, R13, R24). A list section: the import action, then the imported tracks,
// newest first. Tapping a track plays it as In-App Playback; the app owns the picker and the
// library, this view only shows them. AUD-003: a "Queue" row opens the play queue, and each track
// offers Play Next and Add to Queue (swipe right, or the VoiceOver actions).
#if canImport(SwiftUI)
import CaptureKit
import SwiftUI

public struct ImportedAudioSection: View {
    /// Tracks in display order (newest first).
    public let tracks: [ImportedTrack]
    public let isImporting: Bool
    /// Set when the library cannot be used; replaces the import action and the list.
    public let unavailableMessage: String?
    public let onImport: () -> Void
    public let onPlay: (ImportedTrack) -> Void
    public let onRemove: (ImportedTrack) -> Void
    /// AUD-003: the number of queued tracks, and what opens the queue; nil hides the queue row.
    public let queueCount: Int
    public let onShowQueue: (() -> Void)?
    public let onPlayNext: ((ImportedTrack) -> Void)?
    public let onAddToQueue: ((ImportedTrack) -> Void)?

    public init(tracks: [ImportedTrack], isImporting: Bool, unavailableMessage: String? = nil, onImport: @escaping () -> Void,
                onPlay: @escaping (ImportedTrack) -> Void, onRemove: @escaping (ImportedTrack) -> Void,
                queueCount: Int = 0, onShowQueue: (() -> Void)? = nil, onPlayNext: ((ImportedTrack) -> Void)? = nil,
                onAddToQueue: ((ImportedTrack) -> Void)? = nil) {
        self.tracks = tracks
        self.isImporting = isImporting
        self.unavailableMessage = unavailableMessage
        self.onImport = onImport
        self.onPlay = onPlay
        self.onRemove = onRemove
        self.queueCount = queueCount
        self.onShowQueue = onShowQueue
        self.onPlayNext = onPlayNext
        self.onAddToQueue = onAddToQueue
    }

    public var body: some View {
        Section {
            if let unavailableMessage {
                Text(unavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("audioLibraryUnavailable")
            } else {
                importButton
                if let onShowQueue, !tracks.isEmpty {
                    queueButton(onShowQueue)
                }
                if tracks.isEmpty {
                    Text(UIStrings.noImportedAudio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("noImportedAudio")
                }
                ForEach(tracks) { track in
                    row(track)
                }
            }
        } header: {
            Text(UIStrings.yourAudio)
        } footer: {
            Text(UIStrings.importedAudioFooter)
        }
    }

    private var importButton: some View {
        Button(action: onImport) {
            HStack {
                Label(isImporting ? UIStrings.importing : UIStrings.importAudio, systemImage: "square.and.arrow.down")
                if isImporting {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isImporting)
        .accessibilityLabel(Text(isImporting ? UIStrings.importing : UIStrings.importAudio))
        .accessibilityIdentifier("importAudio")
    }

    /// AUD-003: opens the queue.
    private func queueButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(UIStrings.queue, systemImage: "list.bullet")
                Spacer()
                Text("\(queueCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(UIStrings.queueRowLabel(count: queueCount)))
        .accessibilityHint(Text(UIStrings.queueHint))
        .accessibilityIdentifier("queueRow")
    }

    private func row(_ track: ImportedTrack) -> some View {
        Button {
            onPlay(track)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text(UIStrings.duration(track.durationSeconds))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(UIStrings.trackAccessibilityLabel(track)))
        .accessibilityHint(Text(UIStrings.importedTrackHint))
        .accessibilityIdentifier("importedTrack")
        // Swipe to remove; VoiceOver offers the same action in the row's Actions rotor.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onRemove(track)
            } label: {
                Label(UIStrings.remove, systemImage: "trash")
            }
            .accessibilityIdentifier("removeImportedTrack")
        }
        // AUD-003: swipe right for Play Next and Add to Queue; VoiceOver lists them as actions.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onPlayNext {
                Button { onPlayNext(track) } label: { Label(UIStrings.playNext, systemImage: "text.insert") }
                    .tint(.indigo)
                    .accessibilityIdentifier("playNextTrack")
            }
            if let onAddToQueue {
                Button { onAddToQueue(track) } label: { Label(UIStrings.addToQueue, systemImage: "text.append") }
                    .tint(.teal)
                    .accessibilityIdentifier("addToQueueTrack")
            }
        }
    }
}
#endif
