# Contract: shuffle in the play queue (CaptureKit)

Extends `specs/015-aud-003-audio-library-queue/contracts/play-queue.md` and
`specs/017-aud-004-loop-track-and-queue/contracts/repeat-mode.md`.

## API

```swift
public enum PlaybackMove: Sendable { case start, next, previous, endOfTrack }

public protocol MutablePlayOrder: PlayOrder {
    var onOrderChange: (@MainActor () -> Void)? { get set }
    func playbackDidMove(to id: PlaybackItem.ID)
    func playbackDidMove(to id: PlaybackItem.ID, by move: PlaybackMove)   // default: playbackDidMove(to:)
}

extension PlayQueue {
    public private(set) var isShuffled: Bool                // stored; default false
    public func setShuffle(_ on: Bool)                      // draws a seed from seedSource when turning on
    public func setShuffle(_ on: Bool, seed: UInt64)        // tests and reproducible runs
    public func toggleShuffle()
    public var shuffleSeed: UInt64? { get }                 // nil while off
    public var shuffledItems: [PlaybackItem] { get }        // the cycle's order (diagnostics, tests)
    public init(store: PlayQueueStore?, seedSource: @escaping @MainActor () -> UInt64 = <system random>)
}
```

`ShuffleGenerator` (SplitMix64, `bounded`, `shuffle`, `cycleSeed`, `fnv1a64`) is public for tests and
documentation; its outputs are part of the contract: for seed 42, the first three `next()` values are
fixed by golden test values.

## Rules (AUD-005-R1 to R9)

- Shuffle off: every answer is exactly AUD-003/AUD-004's.
- Shuffle on: `item(after:)`, `item(before:)`, `endOfTrack(after:)` and `startItem` follow
  data-model.md. Toggling calls `onOrderChange` (the transport re-evaluates looping only) and stores.
- The transport reports every move with its `PlaybackMove`; the 3-second Previous rule stays in the
  transport.
- `playbackDidMove(to:)` without a reason counts as `.start`.
