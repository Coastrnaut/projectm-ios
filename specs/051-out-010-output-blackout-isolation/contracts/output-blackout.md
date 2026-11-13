# Contract: Output blackout (OUT-010)

## Package API (`PresentationLifecycle`)

```swift
public struct OutputBlackout: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case live, blackedOut, restoreWaiting, fadingIn }
    public static let restoreSpacing: Double          // 1 s of frame time
    public static let maxFrameTime: Double            // 0.1 s
    public static func fadeDuration(reduceFlashing: Bool) -> Double   // 4 s on, 1 s off
    public static func coverOpacity(forLuminanceFactor f: Double) -> Double   // 1 − sRGBEncode(f)

    public init()
    public private(set) var phase: Phase
    public private(set) var luminanceFactor: Double
    public var coverOpacity: Double { get }
    public var isBlack: Bool { get }
    public var isBlackoutRequested: Bool { get }
    public var needsFrames: Bool { get }

    public mutating func blackOut()
    public mutating func restore()
    public mutating func advance(frameTime: Double, reduceFlashing: Bool)
}
```

Guarantees: `blackOut()` makes `isBlack` true and `coverOpacity == 1` before it returns, in every
phase. `restore()` never raises `luminanceFactor` by itself; only `advance` does, by at most
`min(frameTime, 0.1) / fadeDuration` per call. No allocation, no clock, deterministic.

## App (`ExternalDisplayCoordinator`, main actor)

| Member | Contract |
|---|---|
| `setBlackout(_ on: Bool)` | `true`: every slot's cover is opaque, with no animation, before the call returns. `false`: starts or schedules the fade. Never touches the source, the visual or the routing. |
| `toggleBlackout()` | `setBlackout(!isBlackoutRequested)`. |
| `blackoutPhase` (observable) | The model's phase, for the controls, badge and note. |
| `reduceFlashing` | Set by `AppCoordinator` from Settings (FR-072); read at each frame. |
| `advanceFrame(frameTime:)` | The display link's tick (tests call it directly). |

## UI

- Controls: `blackout` button, label "Black out output" (live, fading) or "Restore output"
  (blacked out, restore waiting); accessibility value "Live", "Blacked out", "Restore waiting" or
  "Fading in".
- Badge (`blackoutBadge`, always shown while not live, with or without the controls): "Output
  blacked out" (or "Restoring output…" while waiting or fading) and a `blackoutRestore` button
  (hidden while restoring).
- Device note while external: "External display blacked out" (accessibility label "The external
  display is blacked out") while blackout is requested; otherwise OUT-001's note.
- DEBUG, with `-uitestDiagnostics`: `outputBlackout` (value: `black` when the slot holding the
  visual has an opaque cover, else the phase: `live`, `fadingIn`, …) and `visualRunning`
  (`yes` while the shown visual reports frames).
