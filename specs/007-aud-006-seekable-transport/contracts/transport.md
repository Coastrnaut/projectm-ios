# Contract: transport, play order and the discard operation (AUD-006)

## PCMSink (AudioCore): discarding undelivered audio

```swift
public func discardBufferedAudio()                                   // control side
public func setDiscardHandler(_ handler: (@Sendable () -> Void)?)    // consumer side, once
```

1. The caller owns the producer and guarantees that no `write…` is in flight and none starts
   until the call returns.
2. When the call returns, no sample written before it can reach a consumer: the sink ring is
   empty and, with an `AudioAnalyzer` attached, the converter state and the normalized ring are
   empty and the last levels are silent.
3. It is synchronous, never called from an audio callback, and must not be called from the
   analysis queue. It does not change session statistics, the session start, or the audio state.
4. Without a handler the sink drains its own ring.

`AudioAnalyzer.discardBufferedAudio()` is the handler; it is also callable directly.

## InAppPlaybackBackend (CaptureKit): additions

```swift
var loopsCurrentTrack: Bool { get set }            // default true: one track repeats without a gap
var onTrackEnded: (@MainActor () -> Void)? { get set }   // never called while looping
var position: PlaybackPosition { get }             // (0, 0) when not started
func seek(to seconds: Double)                      // clamped; works playing and paused
func replaceTrack(_ track: InAppPlaybackTrack) throws    // position 0; keeps playing/paused
```

Guarantees:

1. `pause()` holds the position; `resume()` continues from it (AUD-006-R4, R22).
2. After `seek`, `replaceTrack` and `resume`, the first audio written to the sink is the track's
   audio at the new position, and nothing from before the call is written or left downstream
   (AUD-006-R10). The sink's `discardBufferedAudio()` is called exactly once per such call.
   Exception: `replaceTrack` after the current track has played to its end (the automatic
   change) discards nothing; the finished track's tail is delivered, then the new track.
3. `seek` at or past the end: when looping, the position wraps to 0; otherwise the track is at its
   end, `onTrackEnded` is called once (asynchronously) if playing, and on the next `resume()` if
   paused.
4. `replaceTrack` throws `SourceError(.inAppPlaybackFailed)` when the track cannot be loaded; the
   current track is then stopped and silent, and the caller ends the session (AUD-006-R19).
5. `stop()` stays idempotent and ends every pending callback (AUD-006-R29).
6. The tap closure writes only to the sink, behind `PlaybackTapGate`: no allocation, lock, I/O or
   logging (AUD-006-R28).

A backend whose `replaceTrack` failed stays silent: a later `seek` or `resume` does not bring the
old track back.

`InAppPlaybackSource` forwards these and adds `isStarted`, `sessionCount` (incremented by every
successful start) and `reportFailure()` (yields `.failed(.inAppPlaybackFailed)` to the manager).
After a successful `replaceTrack` the source's `track` is the new track, so a Restart plays it.

## CaptureManager (CaptureKit): user pause

```swift
public private(set) var isPausedByUser: Bool
public func pause() async      // In-App Playback only; no effect for other modes
public func resume() async     // existing; now also ends a user pause
```

`pause()` applies the classifier's `suspended` event, so `state == .paused` with no reason and no
banner. Foreground and unlock do not resume a user pause (AUD-006-R21). Everything else in the
lifecycle matrix is unchanged (AUD-006-R22).

## PlayOrder and PlaybackItem

```swift
public struct PlaybackItem: Sendable, Equatable, Identifiable   // id, title, durationSeconds, track
@MainActor public protocol PlayOrder: AnyObject {
    func item(after id: PlaybackItem.ID) -> PlaybackItem?
    func item(before id: PlaybackItem.ID) -> PlaybackItem?
}
@MainActor public final class ListPlayOrder: PlayOrder          // wraps around
```

AUD-003 replaces `ListPlayOrder` with its queue; nil from an order means nothing follows.

## PlaybackTransport

```swift
@MainActor @Observable public final class PlaybackTransport {
    public enum State { case stopped, playing, paused }
    public init(manager: CaptureManager, source: InAppPlaybackSource)
    public var isAvailable: Bool { get }        // an In-App Playback session of `source` is open
    public var state: State { get }             // derived (data-model)
    public private(set) var current: PlaybackItem?
    public var position: PlaybackPosition { get }    // not observable; poll
    public private(set) var positionRevision: Int    // observable; bumped by every jump
    public func prepare(order: any PlayOrder, current: PlaybackItem)   // before the session starts
    public func play() async
    public func pause() async
    public func stop() async
    public func togglePlayPause() async
    public func seek(to seconds: Double)
    public func next() async
    public func previous() async
    public static let previousRestartThreshold = 3.0
}
```

1. Every command is a no-op unless `isAvailable` (AUD-006-R1, R7).
2. `seek` is synchronous: when it returns, `position.seconds` is the clamped target (AUD-006-R9).
3. `prepare` sets the source's track and loop flag; the session itself is started by
   `CaptureManager.select(.inAppPlayback)` as before.
4. The transport never stores a "playing" flag (research AUD-006-D9).

## Rendering side

`NormalizedPCMReader` is unchanged. After a discard the reader returns 0 frames until new audio
has been analyzed (the existing underrun policy).
