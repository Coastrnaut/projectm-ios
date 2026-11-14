# Data Model: CMP-013 Render Caching

All plain Swift in target `Compositor` (`LayerRenderCache.swift`), Sendable, Equatable, Linux-built.

## LayerRenderDependencies

| Field | Type | Meaning |
|---|---|---|
| `time` | Bool | Reads presentation time, frame index or duration |
| `audio` | Bool | Reads the audio context |
| `modulation` | Bool | Has MOD-002 bindings or modulation driving its render |
| `externalInput` | Bool | Reads camera or video frames |
| `contentGeneration` | UInt64 | Changes whenever its content changes (new photo, new rendering) |
| `parameterGeneration` | UInt64 | Changes whenever a parameter it draws with changes (fit) |

`isCacheable` = none of the four flags. `.dynamic` = all flags (convenience).

## LayerRenderCacheKey

`contentGeneration`, `parameterGeneration`, `picture` (`LayerPictureDescriptor`: size, format, colour
space, alpha, origin), `contentScale`, `reduceFlashing`, `epoch`. Built by
`LayerRenderCacheKey(dependencies:picture:contentScale:reduceFlashing:epoch:)`; nil when the
dependencies are nil (undeclared) or not cacheable.

## LayerRenderCacheEntry (per layer record)

State: `key: LayerRenderCacheKey?`.

| Event | Transition |
|---|---|
| `canReuse(key, hasGoodPicture:)` | true only when `key != nil`, `key == stored`, and a good picture exists |
| `willRender()` / `drop()` | `key = nil` (a render may overwrite the picture; a held, failed or skipped frame) |
| `rendered(key)` | `key = key` (only after a successful render; nil stays nil) |

## LayerDrawInput (per layer, level 2)

`picture` (Int, −1 when not drawn), `opacity` (Double), `reused` (Bool). `isUnchanged(from:)`: both
not drawn, or drawn from the same picture with the same opacity and reused this frame.

## Compositor state (Metal)

`isRenderCachingEnabled` (Bool, default true), `renderCacheEpoch` (UInt64), `renderCacheHits` (last
frame), `compositeReused` (last frame), `compositeReuses` (total), `wasReused(layer:)`,
`invalidateRenderCache()`; private `compositeValid`, `lastPoolPurges`, per record `cache`,
`reusedThisFrame`, `drawn`; per group `drawnOpacity`.
