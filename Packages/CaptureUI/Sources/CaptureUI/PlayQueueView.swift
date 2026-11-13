// PlayQueueView.swift — the queue of imported tracks (AUD-003-T15; AUD-003-R5, R10, R11, R17;
// specs/015-aud-003-audio-library-queue/contracts/ui-strings.md). Shown as a sheet from the
// chooser's "Your Audio" section and from the transport while an imported track plays.
//
// "Up Next" lists the queue in order; the current track is marked ("Now Playing" while it plays,
// "Current" otherwise). Reorder three ways: drag in Edit mode, Move Up / Move Down in the row menu
// (touch and hold), or the same VoiceOver actions. Swipe or "Remove from Queue" takes a track out
// of the queue; it stays in Your Audio. "Not in Queue" lists the other library tracks with Add to
// Queue and Play Next. Edits go to `PlayQueue` and never touch playback (AUD-003-R7).
#if canImport(SwiftUI)
import CaptureKit
import SwiftUI

public struct PlayQueueView: View {
    public let queue: PlayQueue
    /// Whether the transport is playing now (the marker reads "Now Playing" then).
    public let isPlaying: Bool
    /// "Play Queue" (chooser only); nil hides the button.
    public let onPlayQueue: (() -> Void)?
    /// Plays a queued track from the chooser; nil makes the rows plain (while the visualizer plays).
    public let onPlay: ((PlaybackItem) -> Void)?
    public let onDone: () -> Void

    #if os(iOS)
    @State private var editMode = EditMode.inactive
    #endif
    @State private var confirmingClear = false

    public init(queue: PlayQueue, isPlaying: Bool, onPlayQueue: (() -> Void)? = nil, onPlay: ((PlaybackItem) -> Void)? = nil,
                onDone: @escaping () -> Void) {
        self.queue = queue
        self.isPlaying = isPlaying
        self.onPlayQueue = onPlayQueue
        self.onPlay = onPlay
        self.onDone = onDone
    }

    public var body: some View {
        let items = queue.items
        let others = queue.notQueued
        List {
            if let onPlayQueue, !items.isEmpty {
                Section {
                    Button(action: onPlayQueue) {
                        Label(UIStrings.playQueue, systemImage: "play.fill")
                    }
                    .accessibilityIdentifier("playQueueButton")
                }
            }
            Section {
                if items.isEmpty {
                    Text(UIStrings.queueEmpty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("queueEmpty")
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    queuedRow(item, position: index + 1, count: items.count)
                }
                .onMove(perform: movePerform)
                .onDelete { offsets in
                    for id in offsets.map({ items[$0].id }) { queue.remove(id) }
                }
            } header: {
                Text(UIStrings.upNext)
            } footer: {
                Text(UIStrings.queueFooter)
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { item in
                        otherRow(item)
                    }
                } header: {
                    Text(UIStrings.notInQueue)
                }
            }
        }
        .accessibilityIdentifier("playQueueView")
        .navigationTitle(UIStrings.queue)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(UIStrings.done, action: onDone)
                    .accessibilityIdentifier("queueDone")
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) {
                EditButton().disabled(items.count < 2)
                Spacer()
                Button(UIStrings.clearQueue, role: .destructive) { confirmingClear = true }
                    .disabled(items.isEmpty)
                    .accessibilityIdentifier("clearQueueButton")
            }
            #endif
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .confirmationDialog(UIStrings.clearQueueConfirm, isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(UIStrings.clearQueue, role: .destructive) { queue.clear() }
                .accessibilityIdentifier("confirmClearQueue")
        }
    }

    /// Drag handles only in Edit mode: outside it, touch and hold opens the row menu.
    private var movePerform: ((IndexSet, Int) -> Void)? {
        #if os(iOS)
        guard editMode.isEditing else { return nil }
        #endif
        return { queue.move(fromOffsets: $0, toOffset: $1) }
    }

    private func marker(for item: PlaybackItem) -> String? {
        guard item.id == queue.currentID else { return nil }
        return isPlaying ? UIStrings.nowPlaying : UIStrings.currentTrack
    }

    @ViewBuilder
    private func queuedRow(_ item: PlaybackItem, position: Int, count: Int) -> some View {
        let marker = marker(for: item)
        let content = HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if let marker {
                    Text(marker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 12)
            Text(UIStrings.duration(item.durationSeconds))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        Group {
            if let onPlay {
                Button { onPlay(item) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(UIStrings.queueRowAccessibilityLabel(title: item.title, durationSeconds: item.durationSeconds,
                                                                      position: position, count: count, marker: marker)))
        .accessibilityAddTraits(onPlay == nil ? [] : .isButton)
        .accessibilityIdentifier("queueEntry")
        .accessibilityAction(named: Text(UIStrings.moveUp)) { move(item, up: true) }
        .accessibilityAction(named: Text(UIStrings.moveDown)) { move(item, up: false) }
        .accessibilityAction(named: Text(UIStrings.removeFromQueue)) { remove(item) }
        .contextMenu {
            Button { move(item, up: true) } label: { Label(UIStrings.moveUp, systemImage: "arrow.up") }
                .disabled(position == 1)
            Button { move(item, up: false) } label: { Label(UIStrings.moveDown, systemImage: "arrow.down") }
                .disabled(position == count)
            Button(role: .destructive) { remove(item) } label: { Label(UIStrings.removeFromQueue, systemImage: "minus.circle") }
        }
    }

    private func otherRow(_ item: PlaybackItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 12)
            Button { add(item, next: false) } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(UIStrings.addToQueue))
            .accessibilityIdentifier("addToQueue")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(item.title), \(UIStrings.spokenDuration(item.durationSeconds))"))
        .accessibilityIdentifier("notQueuedEntry")
        .accessibilityAction(named: Text(UIStrings.addToQueue)) { add(item, next: false) }
        .accessibilityAction(named: Text(UIStrings.playNext)) { add(item, next: true) }
        .contextMenu {
            Button { add(item, next: true) } label: { Label(UIStrings.playNext, systemImage: "text.insert") }
            Button { add(item, next: false) } label: { Label(UIStrings.addToQueue, systemImage: "text.append") }
        }
    }

    // MARK: - Actions (VoiceOver hears the result)

    private func move(_ item: PlaybackItem, up: Bool) {
        if up { queue.moveUp(item.id) } else { queue.moveDown(item.id) }
        guard let index = queue.ids.firstIndex(of: item.id) else { return }
        announce(UIStrings.queueMovedAnnouncement(title: item.title, position: index + 1, count: queue.ids.count))
    }

    private func remove(_ item: PlaybackItem) {
        queue.remove(item.id)
        announce(UIStrings.queueRemovedAnnouncement(title: item.title))
    }

    private func add(_ item: PlaybackItem, next: Bool) {
        if next {
            queue.playNext(item.id)
            announce(UIStrings.playNextAnnouncement(title: item.title))
        } else {
            queue.addToEnd(item.id)
            announce(UIStrings.queueAddedAnnouncement(title: item.title))
        }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
#endif
