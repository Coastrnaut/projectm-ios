// ShuffleState.swift — the shuffled order of the queue and the play history (AUD-005; AUD-005-R2 to
// R8; specs/023-aud-005-shuffle-with-history/data-model.md). Identifiers only; `PlayQueue` owns one
// while Shuffle is on and maps the identifiers to items. Foundation only, all platforms.
//
// * `order` is a permutation of the queue; `order[0..<played]` played in this cycle, in play order
//   (each newly played track moves to index `played`). The rest is the cycle's unplayed part.
// * `history` (at most `historyLimit`) lists the tracks played while shuffled; `cursor` marks the
//   current one. Previous moves back through it, Next forward again before new shuffled tracks.
// * A complete cycle is followed by a new one from `cycleSeed(seed, cycle + 1)` over the queue in
//   queue order; when that starts with the current track it swaps with the last entry, so no track
//   ever follows itself (with two or more queued).
import Foundation

public struct ShuffleState: Sendable, Equatable {
    /// The number of entries the play history keeps; older ones are dropped (AUD-005-R5).
    public static let historyLimit = 100

    public private(set) var seed: UInt64
    public private(set) var cycle: Int
    public private(set) var order: [String]
    public private(set) var played: Int
    public private(set) var history: [String]
    /// The index of the current track in `history`; -1 while the history is empty.
    public private(set) var cursor: Int

    /// Shuffle turned on: a new cycle of `queue`; a queued `current` track is its first, played entry.
    public init(seed: UInt64, queue: [String], current: String?) {
        self.seed = seed
        cycle = 0
        order = ShuffleGenerator.shuffle(queue, seed: ShuffleGenerator.cycleSeed(seed, cycle: 0))
        played = 0
        history = []
        cursor = -1
        if let current {
            if let index = order.firstIndex(of: current) {
                order.remove(at: index)
                order.insert(current, at: 0)
                played = 1
            }
            history = [current]
            cursor = 0
        }
    }

    /// A stored state, repaired against the stored queue (AUD-005-R10): unknown and repeated
    /// entries dropped, missing queued tracks appended in queue order, `played` clamped. The history
    /// is the played part of the cycle, with the cursor at `current` (the tracks played after it,
    /// when the user had gone back, stay ahead); a `current` outside it is appended.
    public init(seed: UInt64, cycle: Int, order stored: [String], played: Int, queue: [String], current: String?) {
        self.seed = seed
        self.cycle = max(0, cycle)
        let queued = Set(queue)
        var seen = Set<String>()
        var order = stored.filter { queued.contains($0) && seen.insert($0).inserted }
        order += queue.filter { !seen.contains($0) }
        self.order = order
        self.played = min(max(0, played), order.count)
        history = Array(order[0..<self.played].suffix(Self.historyLimit))
        cursor = history.count - 1
        guard let current else { return }
        if let index = history.lastIndex(of: current) {
            cursor = index
        } else {
            history.append(current)
            if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
            cursor = history.count - 1
        }
    }

    /// The current track as the history knows it.
    public var currentEntry: String? { cursor >= 0 ? history[cursor] : nil }

    // MARK: - Answers

    /// What Next selects: forward history, else the next unplayed track, else the next cycle's first.
    public func upcoming(queue: [String]) -> String? {
        if cursor + 1 < history.count { return history[cursor + 1] }
        guard !order.isEmpty else { return nil }
        if played < order.count { return order[played] }
        return nextCycleOrder(queue: queue).first
    }

    /// The track to continue with when the current one ends, before repeat rules: forward history or
    /// the next unplayed track. nil when the cycle is complete (the repeat mode decides then).
    public func continuation() -> String? {
        if cursor + 1 < history.count { return history[cursor + 1] }
        return played < order.count ? order[played] : nil
    }

    /// The first track of the next cycle.
    public func nextCycleFirst(queue: [String]) -> String? { nextCycleOrder(queue: queue).first }

    /// What Previous selects (within the 3-second rule): the history entry before the current one;
    /// at the start of the history the current track itself (a restart).
    public var previous: String? { cursor > 0 ? history[cursor - 1] : currentEntry }

    private func nextCycleOrder(queue: [String]) -> [String] {
        var next = ShuffleGenerator.shuffle(queue, seed: ShuffleGenerator.cycleSeed(seed, cycle: cycle + 1))
        if next.count > 1, next[0] == currentEntry { next.swapAt(0, next.count - 1) }
        return next
    }

    // MARK: - Moves

    /// Playback moved to `id`. Moves along the history when that is where the move goes; otherwise
    /// `id` counts as played in the cycle and starts a new branch of the history.
    public mutating func didMove(to id: String, by move: PlaybackMove, queue: [String]) {
        switch move {
        case .previous where cursor > 0 && history[cursor - 1] == id:
            cursor -= 1
            return
        case .next where cursor + 1 < history.count && history[cursor + 1] == id,
             .endOfTrack where cursor + 1 < history.count && history[cursor + 1] == id:
            cursor += 1
            return
        default:
            break
        }
        if currentEntry == id { return }                    // a restart of the current track
        markPlayed(id, queue: queue)
        append(id)
    }

    private mutating func markPlayed(_ id: String, queue: [String]) {
        guard order.contains(id) else { return }            // not queued: history only
        if played >= order.count {
            order = nextCycleOrder(queue: queue)
            cycle += 1
            played = 0
        }
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        if index < played { played -= 1 }
        order.insert(id, at: played)
        played += 1
    }

    private mutating func append(_ id: String) {
        dropForwardHistory()
        history.append(id)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        cursor = history.count - 1
    }

    private mutating func dropForwardHistory() {
        if cursor + 1 < history.count { history.removeSubrange((cursor + 1)...) }
    }

    // MARK: - Edits (AUD-005-R7)

    /// Play Next: right after the current track, also in the shuffle; forward history is dropped.
    public mutating func insertNext(_ id: String) {
        take(id)
        if id == currentEntry {
            order.insert(id, at: played)                    // the current track re-queued: already played
            played += 1
        } else {
            order.insert(id, at: played)
            dropForwardHistory()
        }
    }

    /// A track new to the queue added at the end: the end of the cycle.
    public mutating func append(queued id: String) {
        take(id)
        if id == currentEntry {
            order.insert(id, at: played)
            played += 1
        } else {
            order.append(id)
        }
    }

    /// A new import: a reproducible place in the unplayed part (research AUD-005-D6).
    public mutating func imported(_ id: String) {
        take(id)
        var generator = SplitMix64(seed: seed ^ ShuffleGenerator.fnv1a64(id))
        let position = played + generator.bounded(order.count - played + 1)
        order.insert(id, at: position)
    }

    /// Out of the queue: out of the shuffle, and out of the history except as the current entry.
    public mutating func remove(_ id: String) {
        take(id)
        var index = 0
        while index < history.count {
            if history[index] == id, index != cursor {
                history.remove(at: index)
                if index < cursor { cursor -= 1 }
            } else {
                index += 1
            }
        }
    }

    /// The queue emptied: nothing follows; the current entry stays for Previous.
    public mutating func clear() {
        order = []
        played = 0
        history = currentEntry.map { [$0] } ?? []
        cursor = history.count - 1
    }

    /// Removes `id` from `order`, keeping `played` on the same tracks.
    private mutating func take(_ id: String) {
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        if index < played { played -= 1 }
    }
}
