# Research: MED-005 Video Reverse Playback

## MED-005-D1: Which clips are supported

- **Decision**: the stored copy only; video track ≤ 30 s; upright picture ≤ 1920 × 1080 (longest
  side ≤ 1920, shortest ≤ 1080); decodable. Checked from the probe's track facts before any
  picture is cached; a decode failure during the build is "undecodable".
- **Rationale**: 30 s at 30 pictures/s bounds the cache to 901 pictures; 1080p bounds the decode
  cost of the one-time build. Remote, iCloud-only and protected media cannot be stored (MED-002
  remuxes a local copy), so they need no separate rule.
- **Alternatives**: 60 s (halves cached picture area again); no size limit (a 4K build takes much
  longer and its decode buffers are large).

## MED-005-D2: Cached decode once vs. segment reads

- **Decision**: decode the whole clip once into a downsampled in-memory cache, then select
  pictures from it.
- **Rationale**: H.264/HEVC pictures depend on earlier ones; reading backwards with segment reads
  (decode a group of pictures forward, emit backwards) decodes every group again on every pass,
  needs a full-size group in memory (30 × 8 MB at 1080p) and makes timing depend on decode speed.
  The cache makes the shown picture a pure function of video time, with no decoding on the render
  path, at the cost of resolution.
- **Alternatives**: `AVPlayer` with a negative rate (only for some assets, not through the
  compositor's texture path, and not deterministic for tests); `AVAssetImageGenerator` per picture
  (seek per picture, far too slow).

## MED-005-D3: Budget and accounting

- **Decision**: the budget is MED-008's `AnimatedFrameBudget.current` (32 / 64 / 128 MB by
  physical memory) and every picture is accounted with `AnimatedFrameBudget.accountedFrameBytes`
  (RGBA8 plus one pixel of slack per side). The plan picks the largest size, never above the
  clip's own, such that (pictures + 2 transient) × accounted bytes ≤ budget. A separate
  `VideoReverseFrameStore` keeps every picture (no eviction: reverse needs all of them) and fails
  the build rather than exceed the budget; it records the peak.
- **Rationale**: one memory policy for decoded media across the app; `AnimatedFrameCache`'s LRU
  eviction would silently drop pictures reverse needs.
- **Numbers**: 30 s, 30/s, 16:9 at 64 MB → about 298 × 167; at 128 MB → about 421 × 236.

## MED-005-D4: Picture selection

- **Decision**: with the region [a, b) (MED-003, whole file by default), L = b − a, cached media
  times P (ascending) and a start offset o = b − 1 − s (s = the picture shown when reverse began,
  or b − 1), the shown picture at video time e since the start is the last P[i] ≤
  m = b − 1 − ((e + o) mod L), clamped to the first picture at or after a.
- **Rationale**: pure, integer, wraps from a back to b, honours speed (e is the speed-scaled clock)
  and starts without a jump.

## MED-005-D5: Lifecycle

- **Decision**: the build starts when reverse is on and content is a file (and not suspended);
  forward plays meanwhile. When the render thread first sees the cache ready it stops the forward
  decoder and starts the reverse timeline at the shown picture. Off: cache dropped, forward decoder
  restarted at the shown picture. Suspend: cache and build dropped; resume rebuilds. New content:
  rebuilt for the new file. Unsupported: forward continues, the state carries the reason.
- **Rationale**: matches MED-002-R13 (release everything in the background) and keeps playback
  continuous.

## MED-005-D6: Storage

- **Decision**: `settings.video.reverse` = `{"id": <UUID>}` while reverse is on for that video; no
  key when off. Excluded from FILE-005 backups, erased with "Photos and videos", cleared by a new
  video, Remove Video and the UI tests' reset. Not in scenes.
- **Rationale**: same shape and lifecycle as `settings.video.speed`.
