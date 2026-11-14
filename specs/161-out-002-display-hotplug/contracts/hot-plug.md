# Contract: hot-plug handling (OUT-002)

## C1 Event seam

```swift
@MainActor protocol ExternalDisplayEventSink: AnyObject {
    func externalConnected(id: String, slot: VisualSlotView, geometry: ExternalDisplayGeometry, foreground: Bool)
    func externalResized(id: String, geometry: ExternalDisplayGeometry)
    func externalForeground(id: String, _ foreground: Bool)
    func externalDisconnected(id: String)
}
```

`ExternalDisplayCoordinator` adopts it. Callers: the iOS 26 scene delegate, the iOS 27 accessory, the
DEBUG fake display, unit-test fakes.

## C2 Behaviour

| Event | Settling (pending) | Settled |
|---|---|---|
| connect | slot kept (weak), covered with the current blackout, empty; settle scheduled (0.3 s) | — |
| settle fires (token matches) | routing `.connected`; `place()`; announce X27 | — |
| resize / foreground | updates the pending entry | OUT-001 routing |
| disconnect | cancel: slot released, no move, no announcement | routing `.disconnected`; `place()` in the call; slot emptied and released; announce X28 |

While `holdsPlacement` is true (a recording runs), `place()` uses `effectiveTarget(held:)`: the visual
does not move unless its display is gone. Setting it false calls `place()`.

## C3 Status events (ACC-011 contract C1 rows)

| ID | Transition | Visible / spoken | Kind | Cause | Pres. |
|---|---|---|---|---|---|
| X27 | external display connection settled | "External display connected" (+ " It shows the visualization when the recording ends." while held) | display | S | C |
| X28 | a settled external display disconnected | "External display disconnected" | display | S | C |

## C4 Never

A hot-plug event never creates, pauses, restarts or re-applies a visual host, renderer, compositor,
engine, preset, scene, parameter, the audio source or a recording, and never calls the trails reset.
