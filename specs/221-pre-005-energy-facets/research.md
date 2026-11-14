# Research: PRE-005 Preset Energy Facets

Decisions recorded 2026-11-14 under owner rules 4 and 9.

## PRE-005-D1: Where the frame samples come from

- **Decision**: The PRE-001 thumbnail drawing reads back frames 37, 41 and 45 of its 45 (0-based 36, 40, 44); the last is the thumbnail. A new `PresetThumbnailDrawing.drawSamples` returns the final picture plus the earlier samples; its default implementation (any drawer without samples) returns only the picture.
- **Rationale**: The drawing already loads the preset, feeds deterministic audio and draws 45 frames; two extra `glFinish` + 128 × 72 read-backs cost a few milliseconds against about 1 s per thumbnail. Samples four frames apart (1/15 s) sit inside one beat period of the synthetic audio (frames 30-44), so they measure the preset's own motion rather than the beat restart.
- **Alternatives**: A separate motion render per preset (doubles GPU cost; PRE-001 already rejected whole-library rendering); classifying from the single still frame (no motion information); consecutive frames (too small a change for slow presets to separate from rounding).

## PRE-005-D2: Determinism

- **Decision**: Pin the engine clock: before frame n the runner calls `ProjectMEngine.setFrameTime(n / 60)` (the public `projectm_set_frame_time`), so `time`, `fps` and frame deltas no longer depend on how long shader compiles took. The audio is PRE-001's seeded `SyntheticPCM`. The score is integer arithmetic.
- **Limit**: The engine seeds its own per-preset random values (`rand_start`, `rand_preset`, random textures) from `std::random_device`; the public API offers no seed, and an engine patch is out of scope (Constitution VIII). Presets using them can score differently between drawings. Classes are coarse, so this matters only near a threshold. Recorded in the spec's edge cases.
- **No renderer version bump**: see the spec's clarify session (cached pictures exist only in unreleased builds; a bump would redraw them and rewrite PRE-001's version fixtures). Pictures without a score field simply have no class.

## PRE-005-D3: Score and classes

- **Decision**: For each sample, brightness `Y = (77 R + 150 G + 29 B) >> 8` at the centres of a fixed 32 × 18 grid (independent of picture size). Score = `1000 × Σ|ΔY| / (pairs × 576)` (integer division) over consecutive pairs: thousandths of a brightness level. Classes: Calm < 4,000; Moderate < 16,000; Energetic ≥ 16,000.
- **Rationale**: Integer maths gives bit-identical scores on every platform (acceptance). Mean absolute difference is cheap and monotonic in motion; the grid matches PRE-004's. Thresholds are provisional: a static field changes by 0, slow zooms and drifts by a few levels, busy or strobing presets by tens. Storing the score, not the class, lets a device sweep retune thresholds without migrating data.
- **Alternatives**: Optical flow (costly, not needed for three classes); per-channel RGB difference (colour changes without motion count twice).

## PRE-005-D4: Where the score travels

- **Decision**: `PresetMotionPNG` inserts a PNG `tEXt` chunk `projectM-motion` = `"<scoreVersion>:<score>"` before `IEND` (CRC-32 computed in plain Swift) and reads it back by walking chunks. The app embeds it after encoding the thumbnail; the row's decode task reads it from the same bytes it already loads.
- **Rationale**: The score shares the picture's lifetime (PRE-002 invalidation, Clear Caches, retainOnly) without changing PRE-001's cache or index. Pure Swift, so Linux tests cover it. Another score version in the field is ignored.
- **Alternatives**: A side channel from the renderer to the model keyed by preset bytes (fragile coupling to the cache queue); a field in PRE-001's `index.json` (changes another feature's schema).

## PRE-005-D5: Index and store

- **Decision**: `Library/Caches/PresetMotion/motion.json` = `{"schemaVersion":1,"scoreVersion":1,"entries":{presetID:{thumbnailID,score}}}`. Repair at open as PRE-004-D4 (missing → empty; unreadable, other schema, other score version → empty and saved; current → kept, invalid entries (negative score, empty thumbnail ID) dropped and saved). The store is an actor like `PresetColorStore`: record, coalesced 1 s save (injected sleep), invalidate, retainOnly, flush.
- **Rationale**: A separate file keeps PRE-004's colour schema untouched; the patterns and tests carry over.
- **Fixtures**: `motion-v0.json`, `motion-v99.json`, `motion-corrupt.json`, `motion-score-v0.json`, `motion-v1.json`.

## PRE-005-D6: Filter semantics

- **Decision**: Selected classes combine with OR (they are disjoint); the result joins PRE-004's `filterMatches` with AND. Counts per class are over listed presets with a current score. Announce on the search lane.
- **Alternatives**: AND within classes (always empty with two selected); single selection (less flexible, same code).

## PRE-005-D7: UI test fixture

- **Decision**: The DEBUG `FixtureThumbnailRenderer` (`-uitestThumbnailFixture`) embeds a score derived from the preset bytes (byte sum mod 3 → 1,000 / 8,000 / 30,000), so fixture presets spread over the three classes without the engine.
