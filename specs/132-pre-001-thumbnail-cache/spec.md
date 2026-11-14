# Feature Specification: PRE-001 Visual Thumbnail Cache

**Feature Branch**: `feature/pre-001` (spec directory `132-pre-001-thumbnail-cache`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PRE-001 (visual thumbnail cache) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Generate thumbnails for owned
presets off the main thread." Acceptance, verbatim: "First browse creates thumbnails; second browse
uses cache with stable IDs." Verification: unit + simulator + fixture migrations. P1, size M, no
dependencies."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `PRE-001-R1…`, success criteria `PRE-001-S1…`, tasks `PRE-001-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c0`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit confirms a full gap:
no preset has a picture anywhere in the app.

| Area | Today |
|---|---|
| Preset rows | One shared row view lists every preset (packs, All A-Z, search, Favorites, collections, My Presets): name, subtitle, "May flash", lock or checkmark. No image. |
| Library | `PresetLibrary` (feature 002): 12,847 bundled presets plus the user's imported presets (PRE-012), each with a stable `id` and a content `hash`. Foundation only; tested on Linux. |
| Off-screen rendering | `PresetPrewarmer` (feature 002 SC-104) and `PresetTrialRunner` (PRE-012) already render presets on their own thread with an unshared EGL context, their own engine and a small BGRA8 target. The trial feeds a test tone. A pixel read-back helper exists (`PMANGLEReadPixelsRGBA`). |
| Preset bytes | Included presets are bundle files, pack presets come from the compressed archive, imported presets from the user library's stored copy (playable ones only). |
| Storage usage (FILE-009) | The whole `Library/Caches` folder is the "Caches" category. |
| Cache cleanup (FILE-010) | Clear Caches empties the cleanable categories, including `Library/Caches`, keeping files in use. |
| Erase (FILE-011) | Six categories of user data; caches are not one of them. |
| Later rows | PRE-002 (invalidation after edits or renderer updates), PRE-004 (color facets from thumbnails), PRE-005 (energy facets), PRE-009 (comparison) build on this cache. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which presets are "owned"? → A: Every preset the user can play: the Included presets, pack presets once the library is unlocked, and the user's playable imported presets. A locked pack preset keeps a placeholder (no thumbnail is generated for content the user has not bought), and a waiting or quarantined imported preset is never rendered (it is outside PRE-012's guarded path).
- Q: When are thumbnails generated? → A: Lazily, only for rows the user actually sees in the browser, most recently shown first, one at a time at low priority. Nothing is generated in the background for the whole library (12,847 presets would cost minutes of GPU time and battery the user did not ask for).
- Q: What does a thumbnail show? → A: A small still frame (128 × 72 points of pixels, a 16:9 picture) drawn after a fixed number of frames with deterministic synthetic audio and a fixed seed, so the same preset and renderer always produce the same picture.
- Q: What makes a thumbnail's ID stable? → A: The preset ID, the preset's content hash and the thumbnail renderer version together. The same three always give the same ID and file; a changed preset or a new renderer version gives a new ID (PRE-002 will invalidate old ones).
- Q: Where are thumbnails kept, and how do they fit storage and erase? → A: In a folder inside the app's Caches, excluded from backup, counted in the Storage screen's existing "Caches" category and emptied by Clear Caches (FILE-010). They are rebuildable, so they are not a FILE-011 erase category; erasing My Presets leaves at most orphaned pictures that no row asks for, which Clear Caches removes.
- Q: What if the cache index is damaged or from another version? → A: The cache never blocks browsing: a corrupt index, an index from a newer version, or entries from an older renderer version are discarded (their files deleted) and rebuilt on demand; an entry whose file is missing is dropped and re-rendered when its row appears.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Where do thumbnails appear? → A: Only in the preset browser's rows (every list that uses the shared preset row: packs, All A-Z, search, Favorites, collections, My Presets). Not in the visualizer's controls, where the preset name is enough and a picture would sit over the picture it describes.
- Q: How many thumbnail requests may wait at once? → A: 32. Rows request their thumbnail when they appear; the newest request is served first, and beyond 32 the oldest waiting request is dropped (its row, long scrolled away, asks again if it comes back).
- Q: How is generation throttled while the visualizer runs behind the browser? → A: One thumbnail at a time, at utility priority, with a 150 ms pause after each one, and nothing at all while the app cannot present frames (background, lock). It is not paused merely because the visualizer is visible: the browser covers it and thumbnails are only asked for while the browser is open. The cost is measured on D1 (PRE-001-S7) and the pause can be raised if it fails.
- Q: Which image format is stored? → A: PNG: lossless, so the same render always gives the same bytes, decodable everywhere, and about 10-20 KB at 128 × 72. HEIC saves little at this size and its encoder output is not guaranteed to be stable.
- Q: Is a preset that failed to render remembered across launches? → A: No. A failure is remembered for the session only (the row keeps its placeholder); the next launch tries once more. Failures are not written to the index, so a fixed engine or renderer version heals them without a migration.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I recognize presets by their picture (Priority: P1) — MVP

While browsing presets, each row I can play shows a small picture of what the preset looks like. A
placeholder shows until the picture is ready; scrolling stays smooth.

**Why this priority**: It is the row's observable behavior; names alone ("Geiss - Reaction
Diffusion 2") tell the user little.

**Independent Test**: Open a pack in the browser on a simulator; the first rows show a thumbnail
image (found by accessibility identifier) after a placeholder.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** I open a folder of playable presets, **Then** each visible row shows a placeholder, then its thumbnail once it is generated.
2. **Given** I scroll quickly past many rows, **When** rows leave the screen before their thumbnail is generated, **Then** their pending work is cancelled and the rows now on screen are served first.
3. **Given** a locked pack preset, **When** its row is shown, **Then** it keeps the placeholder and nothing is generated for it.

### User Story 2 - The second browse is instant (Priority: P1)

When I come back to a folder, or relaunch the app, the thumbnails I have seen appear from the cache
without being generated again.

**Why this priority**: It is the row's acceptance: "second browse uses cache with stable IDs".

**Independent Test**: With a counting renderer, a first pass over N presets renders N thumbnails; a
second pass, also after reopening the cache, renders none and returns the same IDs and files.

**Acceptance Scenarios**:

1. **Given** thumbnails generated in a first browse, **When** I browse the same presets again, **Then** no preset is rendered again and each row shows the same thumbnail (same ID, same file).
2. **Given** the app was relaunched, **When** I browse again, **Then** the cache index is read back and still no preset is rendered.

### User Story 3 - A damaged cache repairs itself (Priority: P2)

If the cache is damaged, from another version, or missing files, browsing still works and the
missing thumbnails are generated again.

**Independent Test**: Fixture indexes (an older renderer version, a newer schema, corrupt bytes, an
entry whose file is gone) open without error and lead to re-rendering exactly the affected presets.

**Acceptance Scenarios**:

1. **Given** a corrupt index file, **When** the cache opens, **Then** it starts empty, removes the stale picture files and regenerates on demand.
2. **Given** an index entry whose picture file was deleted, **When** that row appears, **Then** the thumbnail is regenerated and the index updated.
3. **Given** an index written by an older renderer version, **When** the cache opens, **Then** those entries are dropped and their files removed.

### Edge Cases

- A preset that fails to load or draw keeps the placeholder; it is not retried until the next launch.
- The app leaves the screen (background, lock): generation stops and resumes when the app is visible again.
- The visualizer behind the browser keeps running: generation is throttled (one at a time, utility priority, 150 ms between thumbnails) so the visible frame rate is not visibly hurt.
- The same preset shown in two lists (a pack and Favorites) is generated once.
- Clear Caches removes the folder: the cache starts empty again without an error.
- The renderer is unavailable (no ANGLE): rows keep placeholders.
- Disk full: writing fails, the row keeps its placeholder, nothing crashes.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-001-R1**: The browser MUST show a thumbnail or a placeholder at the leading edge of every preset row; the placeholder shows until the thumbnail exists, and always for locked and non-playable presets.
- **PRE-001-R2**: Thumbnails MUST be generated off the main thread, one at a time, at low priority, only for rows the user has shown.
- **PRE-001-R3**: At most 32 requests MUST wait (the oldest is dropped beyond that), served most recent first; a request whose row disappears before its render starts MUST be cancelled.
- **PRE-001-R4**: Each thumbnail MUST be a still frame of a fixed small size drawn after a fixed number of frames with deterministic synthetic audio and a fixed seed.
- **PRE-001-R5**: Each thumbnail MUST have a stable ID derived from the preset ID, the preset's content hash and the renderer version; the same inputs MUST give the same ID and file name.
- **PRE-001-R6**: A thumbnail already in the cache MUST be served without rendering; the same preset requested twice at once MUST be rendered once.
- **PRE-001-R7**: The cache index MUST be stored as a versioned file and read back at the next launch.
- **PRE-001-R8**: A corrupt index, an index with an unknown (newer) version, and entries of an older renderer version MUST be discarded with their files; an entry whose file is missing MUST be dropped and regenerated on demand. Opening the cache MUST never fail.
- **PRE-001-R9**: Thumbnails MUST be stored in the app's Caches, excluded from backup, counted in FILE-009's "Caches" category and removed by FILE-010's Clear Caches; they are not a FILE-011 erase category.
- **PRE-001-R10**: Generation MUST stop while the app cannot present frames and MUST be throttled: one thumbnail at a time, utility priority, a 150 ms pause after each.
- **PRE-001-R14**: Thumbnails MUST be stored as PNG files; they appear only in the preset browser's rows.
- **PRE-001-R11**: A preset that fails to render MUST keep its placeholder and MUST NOT be retried in the same session; failures are not persisted.
- **PRE-001-R12**: Thumbnails are decorative: the row's spoken label MUST stay exactly as before (the picture adds no spoken text and no extra VoiceOver stop); tests may still find the picture by its accessibility identifier.
- **PRE-001-R13**: The cache logic MUST build and be tested on Linux; the renderer MUST sit behind an interface so Linux and tests use a fake.

### Key Entities

- **Thumbnail key**: preset ID, content hash, renderer version; its stable ID names the file.
- **Thumbnail index**: schema version, renderer version, entries (stable ID → preset ID, content hash, renderer version, file name, pixel size).
- **Thumbnail specification**: size, frame count, audio seed, renderer version.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-001-S1**: A first pass over N fixture presets renders exactly N thumbnails; a second pass renders 0 and returns the same N IDs and files (acceptance).
- **PRE-001-S2**: After reopening the cache (relaunch), a pass over the same presets renders 0.
- **PRE-001-S3**: Each migration fixture (older renderer version, newer schema, corrupt index, missing file) opens without error and re-renders exactly the affected presets.
- **PRE-001-S4**: A request cancelled before its render starts renders nothing.
- **PRE-001-S5**: On a simulator, the browser shows thumbnail images for its first rows within the UI test budget (30 s).
- **PRE-001-S6**: The same preset and renderer version always yield the same stable ID, and the synthetic audio is identical for the same seed.
- **PRE-001-S7** `{device}`: On D1, the visualizer's frame rate while thumbnails generate behind the browser stays within 10% of its rate with generation off.

## Assumptions

- The thumbnail's frame rate cost can only be measured on a device; simulator results are never evidence (S7 stays open until a device run).
- Invalidation after an edit (PRE-002) is out of scope; a new content hash simply yields a new ID.
- The cache holds at most the presets the user has scrolled past; no size cap beyond Clear Caches is needed for this row.
