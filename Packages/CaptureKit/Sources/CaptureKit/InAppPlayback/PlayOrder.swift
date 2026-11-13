// PlayOrder.swift — what Next track and Previous track move through (AUD-006-T17; AUD-006-R14 to
// R17; specs/007-aud-006-seekable-transport/contracts/transport.md).
//
// `PlayOrder` is the seam for the queue of AUD-003 and the repeat and shuffle modes of AUD-004 and
// AUD-005: the transport only asks what comes after and before an item. `ListPlayOrder` is a fixed
// list that wraps around (the reference track and test signals, each alone). Imported audio plays
// in the user's queue, `PlayQueue` (AUD-003), a `MutablePlayOrder` that can change while it plays,
// whose repeat mode (AUD-004) decides `endOfTrack(after:)`.
import AudioCore
import Foundation

/// One entry of a play order.
public struct PlaybackItem: Sendable, Equatable, Identifiable {
    /// The id of the bundled reference track's item.
    public static let referenceID = "reference"

    /// Stable within a session: a library track's UUID string, or `referenceID`.
    public let id: String
    public let title: String
    /// From the library record; the transport reports the opened file's own duration when playing.
    public let durationSeconds: Double
    public let track: InAppPlaybackTrack

    public init(id: String, title: String, durationSeconds: Double, track: InAppPlaybackTrack) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.track = track
    }

    /// The bundled reference track (feature 001 FR-006).
    public static func reference(title: String, durationSeconds: Double) -> PlaybackItem {
        PlaybackItem(id: referenceID, title: title, durationSeconds: durationSeconds, track: .reference)
    }

    /// A reference-tone fixture (AUD-016): id `tone.<fixture id>`, the fixture's name as the title,
    /// and its loop as the length. Played alone in its order, so it repeats (AUD-016-R17).
    public static func tone(_ fixture: ReferenceToneFixture) -> PlaybackItem {
        PlaybackItem(id: "tone.\(fixture.id)", title: fixture.name, durationSeconds: Double(fixture.loopSeconds),
                     track: .tone(fixture))
    }

    /// The fixture this item plays, when it is a reference tone.
    public var toneFixture: ReferenceToneFixture? {
        if case .tone(let fixture) = track { return fixture }
        return nil
    }
}

/// Answers what follows and what precedes an item. nil means nothing does (not produced by
/// `ListPlayOrder`; an empty `PlayQueue` gives it).
///
/// `item(after:)` and `item(before:)` are what Next track and Previous track select;
/// `endOfTrack(after:)` is what happens when a track plays to its end, and whether it repeats
/// (AUD-004). By default the end of a track continues with `item(after:)`; the queue answers by its
/// repeat mode instead.
@MainActor
public protocol PlayOrder: AnyObject {
    func item(after id: PlaybackItem.ID) -> PlaybackItem?
    func item(before id: PlaybackItem.ID) -> PlaybackItem?
    func endOfTrack(after id: PlaybackItem.ID) -> EndOfTrackStep
}

extension PlayOrder {
    /// The default: the item after this one, or stop at the end when there is none.
    public func endOfTrack(after id: PlaybackItem.ID) -> EndOfTrackStep {
        item(after: id).map(EndOfTrackStep.play) ?? .stop(cue: nil)
    }
}

/// An order that can change while it plays (AUD-003). The transport sets `onOrderChange` when it
/// takes the order and clears it when another order replaces it; the order calls it after every
/// change, and the transport then re-evaluates only whether the current track repeats
/// (AUD-003-R8). An edit never moves playback by itself (AUD-003-R7).
@MainActor
public protocol MutablePlayOrder: PlayOrder {
    var onOrderChange: (@MainActor () -> Void)? { get set }
    /// The transport selected `id` (prepare, Next, Previous, the end of a track).
    func playbackDidMove(to id: PlaybackItem.ID)
}

/// A fixed list that wraps around: after the last item comes the first, before the first the last.
/// An id that is not in the list (a track removed meanwhile) yields the first item.
@MainActor
public final class ListPlayOrder: PlayOrder {
    public let items: [PlaybackItem]

    public init(_ items: [PlaybackItem]) {
        self.items = items
    }

    public func item(after id: PlaybackItem.ID) -> PlaybackItem? {
        neighbour(of: id, step: 1)
    }

    public func item(before id: PlaybackItem.ID) -> PlaybackItem? {
        neighbour(of: id, step: -1)
    }

    private func neighbour(of id: PlaybackItem.ID, step: Int) -> PlaybackItem? {
        guard !items.isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return items[0] }
        return items[(index + step + items.count) % items.count]
    }
}
