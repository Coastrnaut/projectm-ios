# Contract: Solo and Mute (CMP-012)

## C1 `LayerSoloMute` (plain Swift, every host)

```swift
public struct LayerSoloMute: Sendable, Equatable {
    public init()
    public private(set) var soloedLayers: Set<LayerInstanceID>
    public private(set) var mutedLayers: Set<LayerInstanceID>
    public private(set) var soloedGroups: Set<LayerGroupID>
    public private(set) var mutedGroups: Set<LayerGroupID>
    public var isEmpty: Bool
    public mutating func setSolo(_ on: Bool, layer: LayerInstanceID)
    public mutating func setMute(_ on: Bool, layer: LayerInstanceID)
    public mutating func setSolo(_ on: Bool, group: LayerGroupID)
    public mutating func setMute(_ on: Bool, group: LayerGroupID)
    public mutating func clear()
    public func isSoloed(layer:) / isMuted(layer:) / isSoloed(group:) / isMuted(group:) -> Bool
    public func isSoloActive(in stack: LayerStack) -> Bool
    public func lets(_ entry: LayerStackEntry, in stack: LayerStack) -> Bool
    public func hiddenLayers(in stack: LayerStack) -> Set<LayerInstanceID>
    public func visibleLayers(in stack: LayerStack) -> [LayerInstanceID]   // bottom first, full rule
    public func pruned(to stack: LayerStack) -> LayerSoloMute
}
```

- **Rule** (CMP-012-R3, R4, R5): `lets` = not muted, group not muted, and (no solo active, or the
  layer or its group soloed). `isSoloActive` counts only soloed layers and groups present in the
  stack. Mute wins; a muted solo still counts.
- `visibleLayers` adds the saved conditions: saved opacity > 0 and, for a grouped layer, group
  enabled with opacity > 0.
- Never encoded and never stored in a `LayerStack`.

## C2 Compositor (Metal hosts)

```swift
public private(set) var soloMute: LayerSoloMute
public func setSoloMute(_ overlay: LayerSoloMute)       // between frames, compositor's thread
public func isHiddenBySoloMute(layer index: Int) -> Bool
public private(set) var soloMuteHiddenLayers: Int        // last frame
```

- `setSoloMute` resolves the overlay against the applied stack; `apply` re-resolves it for the new
  stack. Neither prepares, creates nor releases a layer or picture (CMP-012-R6, R10).
- A hidden layer renders every frame as before; it is left out of the composite and of its group's
  isolation decision (R9). Shown from the next frame, no fade (R11). The flash guard's history is
  kept.
- Layers given to `init(device:layers:)` (no stack ID) are never hidden.
- An empty overlay leaves every frame exactly as before (R9).
- **Caller duty**: loading a different scene into a compositor → `setSoloMute(LayerSoloMute())`
  first (restored scenes reuse their saved instance IDs).

## C3 Documents

Scene documents (SCN-001), autosave (SCN-002), undo history (SCN-010), show cues and archives carry
no solo or mute; encoding a scene during a solo gives the same bytes as before it (R2, R8).
