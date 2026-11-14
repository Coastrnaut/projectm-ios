# Research: PRE-001 Visual Thumbnail Cache

Decisions recorded 2026-11-14 under owner rules 4 and 9.

## PRE-001-D1: How is a thumbnail drawn?

- **Decision**: A `PresetThumbnailRunner` in `ANGLERendering`, built like `PresetTrialRunner` (PRE-012): each draw runs on its own thread (utility priority, 768 KiB stack) with an unshared EGL context on the renderer's display, a fresh engine and a BGRA8 framebuffer of 128 × 72; it loads the preset text, feeds 45 frames of synthetic audio (one `addPCMInterleavedStereo` of 735 frames before each `renderFrame`), waits for the GPU and reads the pixels back with `PMANGLEReadPixelsRGBA`, flipped to top-down rows. A timeout (5 s) abandons a draw that never returns; while one is abandoned the runner answers `unavailable`.
- **Rationale**: The proven pattern (CLAUDE.md performance lessons: own thread, unshared context, own engine, window pixel format). The same BGRA format means each draw also warms Metal's pipeline cache for that preset, so playing it from the browser is cheaper afterwards. Per-draw contexts keep no GPU resources while idle (PERF-006).
- **Alternatives**: Reusing the prewarmer's persistent thread (it never reads pixels and its queue semantics replace work); rendering in the visible engine (would disturb the picture); a persistent context (holds memory while the browser is closed).

## PRE-001-D2: Deterministic picture

- **Decision**: `PresetThumbnailSpec` fixes 128 × 72 pixels, 45 frames (0.75 s at 60 fps), 44.1 kHz, 735 samples per frame, seed `0x5052_4531` ("PRE1"). `SyntheticPCM` mixes a 110 Hz and a 440 Hz sine with a beat envelope every 15 frames and seeded noise from a 64-bit linear congruential generator, so every frame block is identical for the same seed. The renderer version (1) covers all of these; changing any of them bumps it.
- **Rationale**: A thumbnail must be reproducible (S6) and show a moving, audio-reactive frame rather than the preset's silent start.
- **Alternatives**: The trial's plain 440 Hz tone (too static for audio-reactive presets); live audio (not deterministic, and private).

## PRE-001-D3: Stable ID

- **Decision**: `stableID` = the first 32 hex digits of SHA-256 over `"<presetID>\n<contentHash>\n<rendererVersion>"` (`PortableSHA256`, Linux-safe); the file is `<stableID>.png`.
- **Rationale**: File-name safe for any preset ID (IDs contain slashes and spaces), fixed length, changes when the preset text or renderer changes (PRE-002 can then delete the old entry by preset ID).

## PRE-001-D4: Index format and migrations

- **Decision**: `index.json` = `{"schemaVersion": 1, "rendererVersion": 1, "entries": {stableID: {presetID, contentHash, rendererVersion, file, width, height}}}`, written atomically after each new thumbnail. Opening repairs, never fails: missing → empty; unreadable or `schemaVersion` above 1 (written by a newer app) → empty and every PNG in the folder removed; entries whose `rendererVersion` differs from the current one → dropped with their files; entries whose file is missing → dropped; PNG files no entry names → removed. A repaired index is saved at once.
- **Rationale**: The cache is rebuildable, so discarding is always safe; repairing at open keeps the hit path a dictionary lookup plus one file-exists check.
- **Fixtures**: `ThumbnailFixtures/index-renderer-v0.json` (an older renderer version), `index-schema-v99.json` (a newer schema), `index-corrupt.json` (truncated JSON), `index-missing-file.json` (two entries, one file present).

## PRE-001-D5: Queue, cancellation, throttle

- **Decision**: The cache is an actor. A request with a cached, existing file returns at once. Otherwise it joins the pending list (one entry per stable ID, extra callers become extra waiters, a repeat moves it to the newest end). A single worker task (utility priority) takes the newest entry, loads its contents, renders, writes the PNG and index, answers every waiter, then sleeps 150 ms through an injected sleep function. Beyond 32 entries the oldest is dropped (waiters get `dropped`). A waiter's task cancellation removes it; an entry with no waiters left is removed before its render starts. A render already started finishes and is cached.
- **Rationale**: Rows scrolled past stop costing anything; the newest rows (on screen) come first; one at a time bounds GPU contention with the visible engine. Injected sleep keeps tests free of wall-clock waits.

## PRE-001-D6: Failure and availability

- **Decision**: A renderer error `unavailable` (no renderer yet, app not presenting, abandoned draw) is passed to waiters and not remembered: the row asks again when it reappears. Any other error (the preset failed to load or draw, or contents could not be read) marks the stable ID failed for the session; later requests fail at once. Nothing about failures is written.

## PRE-001-D7: Storage, backup, Clear Caches and erase

- **Decision**: Folder `Library/Caches/PresetThumbnails`, marked `isExcludedFromBackup` (Caches are not backed up anyway; the flag documents intent). It falls inside FILE-009's "Caches" root (`StorageLocations.roots[.caches]` is the whole Caches folder), so Storage counts it and FILE-010's Clear Caches removes it with no change to either. It is not a FILE-011 erase category: erase removes user-created data, and thumbnails are derived. If the folder disappears while the app runs, the next hit finds its file missing, drops the entry and renders again; the next write recreates the folder.
- **Alternatives**: Application Support (would be backed up and counted as user data); an erase category (would ask the user about something they never made).

## PRE-001-D8: The row

- **Decision**: `PresetThumbnailView` at the leading edge of the shared `PresetRow` (all browser lists), 64 × 36 points, rounded, with a placeholder (a neutral tile with a `sparkles` symbol; a `lock` symbol for locked presets). `.task(id:)` requests the image when the row appears; SwiftUI cancels it when the row disappears. The image is decorative: it adds no spoken text and no VoiceOver stop, so the row's spoken label is unchanged (R12); it keeps an identifier for tests. For the UI test the image carries the identifier `thumbnail:<preset name>` and the placeholder `thumbnailPlaceholder:<preset name>`.
- **Decoded images**: an `NSCache` of `UIImage` keyed by stable ID (evicted by the system under memory pressure).
- **Owned presets**: the model asks for a thumbnail only when the preset is playable (`PresetCoordinator.isPlayable`); user presets load from the user library's playable copy (`userPresetData`), so waiting or quarantined presets are never drawn.

## PRE-001-D9: Frame-rate cost

- **Decision**: Measured on D1 only (`{device}` task PRE-001-T14, S7): the visualizer's fps with the browser open while 20 thumbnails generate, against the same with generation off. Simulator numbers are not evidence. If it fails, raise the pause (a constant) before anything else.
