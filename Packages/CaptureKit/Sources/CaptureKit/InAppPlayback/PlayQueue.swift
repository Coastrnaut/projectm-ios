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
// * Repeat modes (AUD-004): `repeatMode` decides only `endOfTrack(after:)` — what happens when a
//   track plays to its end — never the stored order and never Next or Previous, which wrap in every
//   mode (AUD-004-R7). All Tracks wraps (the default, today's behavior); One Track repeats a queued
//   current track; Off stops after the last queued track and cues the first. A detached current track
//   is never repeated; in Off its former place past the end is the end of the queue (AUD-004-R10).
//   The mode is stored with the queue and a change notifies `onOrderChange` like an edit, so the
//   transport re-evaluates repetition at once without a cut (AUD-004-R9, R14).
// * Shuffle with history (AUD-005; specs/023-aud-005-shuffle-with-history; fulfils AUD-003-R19):
//   while `isShuffled`, a `ShuffleState` on top of `ids` answers Next (`item(after:)`), Previous
//   (`item(before:)`), the end of a track and `startItem`: a seeded shuffled order with a bounded play
//   history, never the same track twice in a row. `ids` (the queue order the user sees) never changes
//   by it. Every edit also updates the shuffled order so that it stays a permutation of `ids`;
//   reorders leave it alone (AUD-005-R7). The repeat mode still decides only the end of a track
//   (AUD-005-R6). Toggling Shuffle is stored and reported like an edit: the transport only
//   re-evaluates looping, so audio is never cut (AUD-005-R9). The transport reports how it moved
//   (`playbackDidMove(to:by:)`), which is how Previous walks back through the history.
import Foundation
import Observation

@MainActor
@Observable
public final class PlayQueue: MutablePlayOrder {
    /// The order, as track ids (UUID strings).
    public private(set) var ids: [PlaybackItem.ID] = []
    /// The track playback last moved to (stored); nil before any.
    public private(set) var currentID: PlaybackItem.ID?
    /// How the queue continues at the end of a track (stored; AUD-004). All Tracks by default.
    public private(set) var repeatMode: RepeatMode = .all
    /// AUD-005: the shuffled order and play history; nil while Shuffle is off (stored).
    public private(set) var shuffle: ShuffleState?
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
    /// Where a new shuffle's seed comes from: the system generator in the app, a fixed value in tests.
    @ObservationIgnored private let seedSource: @MainActor () -> UInt64

    /// Reads the stored queue at once (a small file). `store` nil: a queue in memory only.
    public init(store: PlayQueueStore?, seedSource: @escaping @MainActor () -> UInt64 = { UInt64.random(in: .min ... .max) }) {
        self.store = store
        self.seedSource = seedSource
        switch store?.load() {
        case .record(let record)?:
            ids = record.trackIDs
            currentID = record.currentTrackID
            repeatMode = record.repeatMode
            if let stored = record.shuffle {
                shuffle = ShuffleState(seed: stored.seed, cycle: stored.cycle, order: stored.order, played: stored.played,
                                       queue: record.trackIDs, current: record.currentTrackID)
            }
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

    /// What "Play Queue" starts: the current track when it is queued, otherwise the first (with
    /// Shuffle on, the next track of the shuffled order; AUD-005-R13).
    public var startItem: PlaybackItem? {
        if let currentID, ids.contains(currentID), let item = catalogByID[currentID] { return item }
        if let shuffle, let id = shuffle.upcoming(queue: ids), let item = catalogByID[id] { return item }
        return items.first
    }

    // MARK: - Shuffle (AUD-005)

    public var isShuffled: Bool { shuffle != nil }
    /// The seed of the current shuffle; nil while Shuffle is off.
    public var shuffleSeed: UInt64? { shuffle?.seed }
    /// The cycle's shuffled order (empty while Shuffle is off).
    public var shuffledItems: [PlaybackItem] { shuffle?.order.compactMap { catalogByID[$0] } ?? [] }

    /// Turns Shuffle on (with a new seed from `seedSource`) or off. The same value again does nothing.
    public func setShuffle(_ on: Bool) {
        guard on != isShuffled else { return }
        setShuffle(on, seed: on ? seedSource() : 0)
    }

    /// Turns Shuffle on with `seed` (reproducible), or off. Stored and reported like an edit; never
    /// moves playback (AUD-005-R9). Turning it off forgets the history.
    public func setShuffle(_ on: Bool, seed: UInt64) {
        guard on != isShuffled else { return }
        shuffle = on ? ShuffleState(seed: seed, queue: ids, current: currentID) : nil
        changed()
    }

    public func toggleShuffle() {
        setShuffle(!isShuffled)
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
            shuffle?.imported(id)
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
            shuffle?.insertNext(id)
            changed()
            return
        }
        if ids.contains(id) { removeKeepingShuffle(id) }     // `insertNext` moves it in the shuffle
        let position: Int
        if let currentID, let index = ids.firstIndex(of: currentID) {
            position = index + 1
        } else if let detachedIndex {
            position = min(detachedIndex, ids.count)
        } else {
            position = 0
        }
        insert(id, at: position)
        shuffle?.insertNext(id)
        changed()
    }

    /// Places a library track at the end. A queued track moves there.
    public func addToEnd(_ id: PlaybackItem.ID) {
        guard catalogByID[id] != nil else { return }
        if ids.last == id { return }
        let wasQueued = ids.contains(id)
        if wasQueued { removeKeepingShuffle(id) }            // a reorder: the shuffled order stays (AUD-005-R7)
        insert(id, at: ids.count)
        if !wasQueued { shuffle?.append(queued: id) }
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
        shuffle?.clear()
        changed()
    }

    // MARK: - PlayOrder

    public func item(after id: PlaybackItem.ID) -> PlaybackItem? {
        if let shuffle {
            return shuffle.upcoming(queue: ids).flatMap { catalogByID[$0] }
        }
        return neighbour(of: id, step: 1)
    }

    public func item(before id: PlaybackItem.ID) -> PlaybackItem? {
        if let shuffle {
            return catalogByID[shuffle.previous ?? id]
        }
        return neighbour(of: id, step: -1)
    }

    /// What follows when `id` plays to its end, by repeat mode (AUD-004; data-model.md table), and
    /// while shuffled by the shuffled order (AUD-005-R6).
    public func endOfTrack(after id: PlaybackItem.ID) -> EndOfTrackStep {
        if let shuffle { return shuffledEndOfTrack(after: id, shuffle) }
        let queued = items
        guard let first = queued.first else { return .stop(cue: nil) }
        let index = queued.firstIndex(where: { $0.id == id })
        if let index {
            switch repeatMode {
            case .one: return .play(queued[index])
            case .off where index == queued.count - 1: return .stop(cue: first)
            case .off, .all: return .play(queued[(index + 1) % queued.count])
            }
        }
        if id == currentID, let detachedIndex, repeatMode == .off, detachedIndex >= queued.count {
            return .stop(cue: first)                   // the removed track was last: the end of the queue
        }
        return item(after: id).map(EndOfTrackStep.play) ?? .stop(cue: nil)
    }

    /// AUD-005-R6: One Track repeats a queued current track; otherwise forward history or the next
    /// unplayed track; after a complete cycle, the next cycle's first track (Off: stop and cue it).
    private func shuffledEndOfTrack(after id: PlaybackItem.ID, _ shuffle: ShuffleState) -> EndOfTrackStep {
        guard !ids.isEmpty else { return .stop(cue: nil) }
        if repeatMode == .one, ids.contains(id), let item = catalogByID[id] { return .play(item) }
        if let next = shuffle.continuation().flatMap({ catalogByID[$0] }) { return .play(next) }
        guard let first = shuffle.nextCycleFirst(queue: ids).flatMap({ catalogByID[$0] }) else { return .stop(cue: nil) }
        return repeatMode == .off ? .stop(cue: first) : .play(first)
    }

    // MARK: - Repeat mode (AUD-004)

    /// Sets the repeat mode: stored at once and reported like an edit, so that the transport applies
    /// it to the playing track without moving it (AUD-004-R9). The same mode again does nothing.
    public func setRepeatMode(_ mode: RepeatMode) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        changed()
    }

    /// The Repeat control's tap: Off → All Tracks → One Track → Off (AUD-004-R12).
    public func cycleRepeatMode() {
        setRepeatMode(repeatMode.next)
    }

    public func playbackDidMove(to id: PlaybackItem.ID) {
        playbackDidMove(to: id, by: .start)
    }

    public func playbackDidMove(to id: PlaybackItem.ID, by move: PlaybackMove) {
        if id != currentID || ids.contains(id) { detachedIndex = nil }
        currentID = id
        shuffle?.didMove(to: id, by: move, queue: ids)
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

    /// `removeID` for a track that stays queued (a move): the shuffle and its history are kept.
    private func removeKeepingShuffle(_ id: PlaybackItem.ID) {
        let kept = shuffle
        removeID(id)
        shuffle = kept
    }

    /// Removes `id`; the current track detaches at its index, and a detached index before which an
    /// entry was removed moves with it.
    private func removeID(_ id: PlaybackItem.ID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        shuffle?.remove(id)
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
                                        currentTrackID: currentID.flatMap(PlayQueueRecord.canonicalID),
                                        repeatMode: repeatMode,
                                        shuffle: shuffle.map(Self.record)))
    }

    /// The stored form of the shuffle state (identifiers canonical, as the queue's).
    private static func record(_ shuffle: ShuffleState) -> PlayQueueRecord.Shuffle {
        PlayQueueRecord.Shuffle(seed: shuffle.seed, cycle: shuffle.cycle,
                                order: shuffle.order.compactMap(PlayQueueRecord.canonicalID), played: shuffle.played)
    }
}
