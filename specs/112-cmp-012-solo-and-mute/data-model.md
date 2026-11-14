# Data Model: CMP-012 Solo and Mute

## LayerSoloMute (new, plain Swift, `Compositor`)

| Field | Type | Meaning |
|---|---|---|
| `soloedLayers` | `Set<LayerInstanceID>` | Layers soloed |
| `mutedLayers` | `Set<LayerInstanceID>` | Layers muted |
| `soloedGroups` | `Set<LayerGroupID>` | Groups soloed |
| `mutedGroups` | `Set<LayerGroupID>` | Groups muted |

- Value type, `Sendable`, `Equatable`. Default: empty (nothing soloed or muted).
- Operations: `setSolo(_:layer:)`, `setMute(_:layer:)`, `setSolo(_:group:)`, `setMute(_:group:)`,
  `clear()`; queries `isSoloed`, `isMuted`, `isEmpty`, `isSoloActive(in:)`, `lets(_:in:)`,
  `hiddenLayers(in:)`, `visibleLayers(in:)`, `pruned(to:)`.
- Never encoded; no `Codable` conformance on purpose.

## Effective visibility (derived)

`visible(entry) = shown && opacity > 0 && groupOn && groupOpacity > 0 && overlay.lets(entry)`.
`visibleLayers(in:)` evaluates the stack-level part (saved opacity, group on/off and opacity), the
compositor adds "has a picture this frame" and the animated opacity.

## Compositor additions

| Member | Meaning |
|---|---|
| `LayerRecord.overlayHidden: Bool` | Resolved at `apply` / `setSoloMute`; false for layers without a stack ID |
| `soloMute: LayerSoloMute` (read) / `setSoloMute(_:)` | The overlay |
| `isHiddenBySoloMute(layer:) -> Bool` | Per layer index, next frame |
| `soloMuteHiddenLayers: Int` | Layers the overlay hid in the last frame |

## Unchanged

`LayerStack`, `LayerStackEntry`, `LayerGroup`, `SceneDocument` and every saved field.
