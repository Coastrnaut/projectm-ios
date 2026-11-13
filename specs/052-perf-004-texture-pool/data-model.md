# Data Model: PERF-004 Texture Pool

## TexturePoolKey (value, plain Swift)

| Field | Type | Rule |
|---|---|---|
| pixelFormat | UInt | `MTLPixelFormat.rawValue` |
| width, height | Int | ≥ 1 |
| depth, arrayLength | Int | ≥ 1 (1 for 2D pictures) |
| usage | UInt | `MTLTextureUsage.rawValue` |
| storageMode | UInt | `MTLStorageMode.rawValue` |
| mipmapLevelCount | Int | ≥ 1 |
| sampleCount | Int | ≥ 1 |
| textureType | UInt | `MTLTextureType.rawValue` |

Hashable; two textures are interchangeable only when their keys are equal (PERF-004-R1).

## TexturePoolLimits (value)

| Field | Default | Rule |
|---|---|---|
| maxRetiredBytes | min(128 MiB, recommendedMaxWorkingSetSize / 8) | ≥ 0; 0 keeps nothing |
| maxIdleFrames | 300 | ≥ 0; entries retired more than this many ticks ago are dropped |

## TexturePoolCounters (value)

`liveTextures`, `liveBytes` (checked out + retired), `checkedOutTextures`, `checkedOutBytes`,
`retiredTextures`, `retiredBytes` (idle + waiting), `waitingTextures` (fence not complete at the last
look), `hits`, `misses`, `evictions` (cap or age), `purged` (dropped by `purge()`), `purges`.

Invariants: `liveTextures == checkedOutTextures + retiredTextures`; `retiredBytes ≤ maxRetiredBytes`
after every `checkIn`; `hits + misses` = check-outs.

## Pool entry states

```text
           checkOut (miss: created, adopt)        checkIn(fence)
 (none) ───────────────────────────────▶ checked out ───────────────▶ retired (waiting)
                                            ▲                              │ fence complete or nil
                                            │ checkOut (hit, same key)     ▼
                                            └──────────────────────── retired (idle)
 retired ──(cap: LRU first | age > maxIdleFrames | purge)──▶ dropped (released)
```

- A waiting entry is never handed out (PERF-004-R2). A waiting or idle entry may be dropped.
- Returning a texture the pool does not know (or twice) is ignored and reported `false`.

## Compositor ↔ pool

| Moment | Compositor action |
|---|---|
| First frame / size change | `checkIn` old composite and pictures (fence = last command buffer), then `checkOut` new ones |
| `apply` adds a layer (size known) | `checkOut` its pictures |
| `apply` removes a layer | `checkIn` its pictures (fence = last command buffer) |
| Every `composite` | `tick()`; remember `commandBuffer` as the fence |
| `deinit` | `checkIn` everything (fence = last command buffer) |
