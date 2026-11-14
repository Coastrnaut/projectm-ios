# Contract: FrameDropCounter (PERF-007)

## C1 Counter (FrameTiming, pure Swift, Linux)

```swift
public final class FrameDropCounter: Sendable {
    public init()
    @discardableResult public func beginSession(measuresPresentation: Bool) -> FrameDropSession
    public var session: FrameDropSession { get }
    /// Frame path. Nil when the session is stale or the timestamp is not later than the previous one.
    public func submit(_ session: FrameDropSession, timestamp: Double, targetTimestamp: Double) -> FrameDropTicket?
    /// Any thread. Counted at most once per ticket frame ID.
    public func presented(_ ticket: FrameDropTicket, presentedTime: Double)
    public func counts() -> FrameDropCounts
}
```

- `submit`: submitted += 1; skipped += max(round((timestamp − previous) / interval) − 1, 0) when a previous timestamp exists and the interval is finite and > 0.
- `presented`: stale ticket → stale += 1. Repeated or too-old ID → no change. Else `presentedTime ≤ 0` → discarded += 1; otherwise presented += 1 and late += 1 when `presentedTime − targetTime > interval / 2`.
- `counts()`: `presented`, `late`, `discarded` are nil unless the session measures presentation.
- `FrameDropCounts.recording(written:droppedSlots:)`: presented = written, skipped = droppedSlots, others nil.

## C2 Overlay lines

`FrameDropCounts.line(for:)` → `frames device: presented N, late N, skipped N, submitted N, discarded N`
(recording: `frames recording: presented N, late unavailable, skipped N`); nil → `unavailable`. The overlay shows
lines starting with `frames ` in their own text, identifier `overlayFrameDrops`.

## C3 Export

`DiagnosticsSnapshot.frameDrops` (optional): `{ "outputs": [ { "output": "device", "submitted": 300, "skipped": 2, "stale": 0 } ] }`; nil values are absent keys.
