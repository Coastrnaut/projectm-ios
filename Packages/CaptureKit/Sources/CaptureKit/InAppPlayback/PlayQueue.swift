// PlayQueue.swift — the user's queue of imported tracks, the play order of imported audio (AUD-003;
// specs/015-aud-003-audio-library-queue/data-model.md and contracts/play-queue.md).
//
// * The queue is an ordered list of library track ids, each at most once (AUD-003-R1). Without a
//   stored record it starts as the library list order (newest first, AUD-003-R2); new imports
//   join at the top (R3). Removing from the queue never deletes a track; a track that left the
//   library leaves the queue (R6).
// * Edits (play next, add to end, remove, move, clear) never call the transport's commands: they
//   only change what `item(after:)` and `item(before:)` answer from then on, and notify
//   `onOrderChange` so that the transport can re-evaluate whether the playing track repeats
//   (AUD-003-R7, R8). They are not transport changes for interruption recovery (R12).
// * The playing track removed from the queue is "detached": it plays on to its end, then the entry
//   now at its former index follows (wrapping); with an empty queue nothing follows (R9). The index
//   follows removals and insertions before it, so the same track stays next.
// * Every edit and every move of playback is stored at once (`PlayQueueStore`, atomic), unless the
//   stored record was written by a newer app (R13, R14). A failed write keeps the queue in memory
//   and the previous file; the next change tries again.
// * Repeat modes (AUD-004) and shuffle with history (AUD-005) can be added on top of `ids`: both
//   change only what the neighbour functions answer, not the stored order (R19).
import Foundation
import Observation

@MainActor
@Observable
public final class PlayQueue: MutablePlayOrder {
    /// The order, as track ids (UUID strings).
    public private(set) var ids: [PlaybackItem.ID] = []
    /// The track playback last moved to (stored); nil before any.
    public private(set) var currentID: PlaybackItem.ID?
    /// False when no store was given, or the stored record is newer than this app: edits then
    /// work for this launch and are not stored.
    public private(set) var isPersistent: Bool
    /// The library's tracks by id, in library list order.
    private var catalog: [PlaybackItem] = []
    private var catalogByID: [PlaybackItem.ID: PlaybackItem] = [:]
    /// Set while the current track is not queued (removed while current): its former index.
    private var detachedIndex: Int?
    /// No record was read: the first library seeds the queue.
    private var needsSeed: Bool
    /// `setLibrary` has not run yet.
    private var isFirstLibrary = true

    @ObservationIgnored public var onOrderChange: (@MainActor () -> Void)?
    @ObservationIgnored private let store: PlayQueueStore?

    /// Reads the stored queue at once (a small file). `store` nil: a queue in memory only.
    public init(store: PlayQueueStore?) {
        self.store = store
        switch store?.load() {
        case .record(let record)?:
            ids = record.trackIDs
            currentID = record.currentTrackID
            isPersistent = true
            needsSeed = false
        case .newerFormat?:
            isPersistent = false
            needsSeed = true
        case .missing?, .damaged?:
            isPersistent = true
            needsSeed = true
        case nil:
            isPersistent = false
            needsSeed = true
        }
    }

    // MARK: - What is queued

    /// The queued tracks, in order.
    public var items: [PlaybackItem] { ids.compactMap { catalogByID[$0] } }
    /// The library's tracks that are not queued, in library order.
    public var notQueued: [PlaybackItem] {
        let queued = Set(ids)
        return catalog.filter { !queued.contains($0.id) }
    }

    public func contains(_ id: PlaybackItem.ID) -> Bool { ids.contains(id) }

    /// What "Play Queue" starts: the current track when it is queued, otherwise the first.
    public var startItem: PlaybackItem? {
        if let currentID, ids.contains(currentID), let item = catalogByID[currentID] { return item }
        return items.first
    }

    // MARK: - The library

    /// The library's tracks in list order, after every load, import or removal. Call only while
    /// the library is ready: tracks missing here leave the queue (AUD-003-R6).
    public func setLibrary(_ library: [PlaybackItem]) {
        catalog = library
        catalogByID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if needsSeed {
            needsSeed = false
            isFirstLibrary = false
            ids = library.map(\.id)
            changed(store: false)
            return
        }
        let kept = ids.filter { catalogByID[$0] != nil }
        if kept != ids {
            for id in ids.reversed() where catalogByID[id] == nil { removeID(id) }
            changed()
        }
        // A stored current track that left the library is forgotten at load. Later, a current
        // track deleted from the library stays detached until playback moves (AUD-003-R9).
        if isFirstLibrary, let currentID, catalogByID[currentID] == nil {
            self.currentID = nil
            detachedIndex = nil
            save()
        }
        isFirstLibrary = false
    }

    /// Tracks just imported, in import order: unknown ones join at the top, the last one first,
    /// as "Your Audio" lists them (AUD-003-R3).
    public func didImport(_ imported: [PlaybackItem.ID]) {
        var added = false
        for id in imported where catalogByID[id] != nil && !ids.contains(id) {
            insert(id, at: 0)
            added = true
        }
        if added { changed() }
    }

    // MARK: - Edits (AUD-003-R5)

    /// Places a library track right after the current track (at the top when there is none). A
    /// queued track moves there.
    public func playNext(_ id: PlaybackItem.ID) {
        guard catalogByID[id] != nil else { return }
        if id == currentID, ids.contains(id) { return }
        if id == currentID, let detachedIndex {
            // The detached current track queued again, in its place.
            insert(id, at: min(detachedIndex, ids.count))
            self.detachedIndex = nil
            changed()
            return
        }
        if ids.contains(id) { removeID(id) }
        let position: Int
        if let currentID, let index = ids.firstIndex(of: currentID) {
            position = index + 1
        } else if let detachedIndex {
            position = min(detachedIndex, ids.count)
        } else {
            position = 0
        }
        insert(id, at: position)
        changed()
    }

    /// Places a library track at the end. A queued track moves there.
    public func addToEnd(_ id: PlaybackItem.ID) {
        guard catalogByID[id] != nil else { return }
        if ids.last == id { return }
        if ids.contains(id) { removeID(id) }
        insert(id, at: ids.count)
        if id == currentID { detachedIndex = nil }
        changed()
    }

    /// Takes a track out of the queue; it stays in the library.
    public func remove(_ id: PlaybackItem.ID) {
        guard ids.contains(id) else { return }
        removeID(id)
        changed()
    }

    /// Moves the entries at `offsets` to before `destination`, as SwiftUI's `onMove` reports it.
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty, offsets.allSatisfy({ ids.indices.contains($0) }),
              (0...ids.count).contains(destination) else { return }
        let moved = offsets.map { ids[$0] }
        var remaining = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let target = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: target)
        guard remaining != ids else { return }
        ids = remaining
        changed()
    }

    public func moveUp(_ id: PlaybackItem.ID) {
        guard let index = ids.firstIndex(of: id), index > 0 else { return }
        ids.swapAt(index, index - 1)
        changed()
    }

    public func moveDown(_ id: PlaybackItem.ID) {
        guard let index = ids.firstIndex(of: id), index + 1 < ids.count else { return }
        ids.swapAt(index, index + 1)
        changed()
    }

    /// Empties the queue; the tracks stay in the library. A playing track plays to its end.
    public func clear() {
        guard !ids.isEmpty else { return }
        if let currentID, ids.contains(currentID) || detachedIndex != nil { detachedIndex = 0 }
        ids = []
        changed()
    }

    // MARK: - PlayOrder

    public func item(after id: PlaybackItem.ID) -> PlaybackItem? {
        neighbour(of: id, step: 1)
    }

    public func item(before id: PlaybackItem.ID) -> PlaybackItem? {
        neighbour(of: id, step: -1)
    }

    public func playbackDidMove(to id: PlaybackItem.ID) {
        if id != currentID || ids.contains(id) { detachedIndex = nil }
        currentID = id
        save()
    }

    private func neighbour(of id: PlaybackItem.ID, step: Int) -> PlaybackItem? {
        let queued = items
        guard !queued.isEmpty else { return nil }
        let count = queued.count
        if let index = queued.firstIndex(where: { $0.id == id }) {
            return queued[(index + step + count) % count]
        }
        if id == currentID, let detachedIndex {
            // The removed current track: the entry at its former place follows, the one before it precedes.
            let next = detachedIndex % count
            return queued[step > 0 ? next : (detachedIndex - 1 + count) % count]
        }
        return queued[0]
    }

    // MARK: - Bookkeeping

    private func insert(_ id: PlaybackItem.ID, at index: Int) {
        ids.insert(id, at: index)
        if let detachedIndex, index < detachedIndex { self.detachedIndex = detachedIndex + 1 }
    }

    /// Removes `id`; the current track detaches at its index, and a detached index before which an
    /// entry was removed moves with it.
    private func removeID(_ id: PlaybackItem.ID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        if id == currentID {
            detachedIndex = index
        } else if let detachedIndex, index < detachedIndex {
            self.detachedIndex = detachedIndex - 1
        }
    }

    private func changed(store shouldStore: Bool = true) {
        if shouldStore { save() }
        onOrderChange?()
    }

    private func save() {
        guard isPersistent, let store else { return }
        try? store.save(PlayQueueRecord(trackIDs: ids.compactMap(PlayQueueRecord.canonicalID),
                                        currentTrackID: currentID.flatMap(PlayQueueRecord.canonicalID)))
    }
}
