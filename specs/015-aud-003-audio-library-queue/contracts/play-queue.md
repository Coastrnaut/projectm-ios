# Contract: PlayQueue and the transport (AUD-003)

`CaptureKit`, `@MainActor`.

```swift
public protocol MutablePlayOrder: PlayOrder {
    var onOrderChange: (@MainActor () -> Void)? { get set }
    func playbackDidMove(to id: PlaybackItem.ID)
}

@Observable public final class PlayQueue: MutablePlayOrder {
    public init(store: PlayQueueStore?)            // nil: in memory only
    public private(set) var items: [PlaybackItem]
    public private(set) var notQueued: [PlaybackItem]
    public private(set) var currentID: PlaybackItem.ID?
    public private(set) var isPersistent: Bool
    public func setLibrary(_ items: [PlaybackItem])
    public func didImport(_ ids: [PlaybackItem.ID])
    public func contains(_ id: PlaybackItem.ID) -> Bool
    public func playNext(_ id: PlaybackItem.ID)
    public func addToEnd(_ id: PlaybackItem.ID)
    public func remove(_ id: PlaybackItem.ID)
    public func move(fromOffsets: IndexSet, toOffset: Int)
    public func moveUp(_ id: PlaybackItem.ID)
    public func moveDown(_ id: PlaybackItem.ID)
    public func clear()
    public var startItem: PlaybackItem?           // "Play Queue": current if queued, else first
    public func item(after:) / item(before:)       // PlayOrder
}

public struct PlayQueueStore: Sendable {
    public init(directory: URL)                    // writes <directory>/queue.json
    public func load() -> PlayQueueStore.Loaded    // .missing, .record, .damaged, .newerFormat
    public func save(_ record: PlayQueueRecord) throws
}
```

Guarantees:

1. Edits never call the transport's commands; the transport only re-evaluates looping
   (AUD-003-R7, R8, R12).
2. `item(after:)`/`item(before:)` read the queue as it is now (AUD-003-R1).
3. A save failure keeps the in-memory queue and the previous file (atomic write); the next edit
   tries again.
4. `setLibrary` is called only with a ready library (never with the empty list of an unavailable one).

Backend addition: `func updateLooping(_ loops: Bool)` on `InAppPlaybackBackend` (default: sets
`loopsCurrentTrack`). Effect now, position kept, no cut, no state change; while held only the flag.
