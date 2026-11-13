# Contract: repeat modes in CaptureKit (AUD-004)

```swift
public enum RepeatMode: String, Sendable, CaseIterable {
    case off, one, all
    public var next: RepeatMode            // off → all → one → off
}

public enum EndOfTrackStep: Sendable, Equatable {
    case play(PlaybackItem)                // the same item as the current one: it repeats gaplessly
    case stop(cue: PlaybackItem?)          // stop at the end; a cue waits, stopped, at its 0:00
}

@MainActor public protocol PlayOrder: AnyObject {
    func item(after id: PlaybackItem.ID) -> PlaybackItem?      // Next track (unchanged)
    func item(before id: PlaybackItem.ID) -> PlaybackItem?     // Previous track (unchanged)
    func endOfTrack(after id: PlaybackItem.ID) -> EndOfTrackStep   // new
}
extension PlayOrder {
    // Default: item(after:) as .play, nil as .stop(cue: nil). ListPlayOrder uses it.
    public func endOfTrack(after id: PlaybackItem.ID) -> EndOfTrackStep
}

extension PlayQueue {
    public private(set) var repeatMode: RepeatMode             // observable; stored
    public func setRepeatMode(_ mode: RepeatMode)              // stores, then onOrderChange
    public func cycleRepeatMode()                              // setRepeatMode(repeatMode.next)
    public func endOfTrack(after id: PlaybackItem.ID) -> EndOfTrackStep   // data-model.md table
}

public struct PlayQueueRecord {
    public var repeatMode: RepeatMode                          // default .all
    public init(trackIDs: [String], currentTrackID: String?, repeatMode: RepeatMode = .all)
}
```

## Transport rules (`PlaybackTransport`)

1. `loops(current)` ⇔ `order.endOfTrack(after: current.id) == .play(current)`. Re-evaluated in
   `prepare`, every track change and `orderDidChange()` (a mode change calls it through
   `onOrderChange`), applied with `source.updateLooping` (no cut, position kept).
2. End of a track while playing: `.play(item)` → `change(to: item)` (no cut at a natural end);
   `.stop(cue)` → `manager.pause(asStop: true)`; then, with a cue, `change(to: cue)` while paused
   (held at 0:00); the session is marked stopped. State: Stopped.
3. `play()` while paused or stopped at the very end of a non-looping track: `.play(item)` → change
   and resume; `.stop(cue: item)` → change to the cue and resume; `.stop(cue: nil)` → nothing.
4. `next()`/`previous()`: unchanged (`item(after:)`, `item(before:)`, 3-second rule).
5. A mode change sends no command to the backend except `updateLooping` when the loop flag changes,
   and never calls `noteUserTransportChange()`.
