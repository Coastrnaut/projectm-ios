# Feature Specification: PRE-002 Thumbnail Invalidation

**Feature Branch**: `feature/pre-002` (spec directory `144-pre-002-thumbnail-invalidation`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PRE-002 (thumbnail invalidation) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Refresh thumbnail after user
preset changes or renderer version updates." Acceptance, verbatim: "Changed preset invalidates
exactly its thumbnail and not neighbors." Verification: unit + simulator + fixture migrations. P1,
size S, depends on PRE-001."

Identifiers in this feature carry the roadmap ID: requirements `PRE-002-R1…`, success criteria
`PRE-002-S1…`, tasks `PRE-002-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `09621948`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit finds a partial gap.

| Area | Today (PRE-001, specs/132-pre-001-thumbnail-cache) |
|---|---|
| Thumbnail key | Stable ID from preset ID, content hash and renderer version. A changed preset already maps to a new ID and file, so the row never shows the old picture for new content. |
| Row refresh | The row's request is keyed by preset ID and content hash, so a new hash makes the row ask again once the browser lists the changed preset. |
| Old picture after an edit | **Leaks.** The old entry and file stay in the index for good: opening drops only entries of another renderer version or with a missing file, and the old entry is neither. |
| Deleted user preset | **Leaks.** Its entry and file stay until Clear Caches. |
| Renamed user preset | Its ID (`user/<random>`) and content do not change, so the thumbnail stays valid. |
| Renderer version | A hand-set constant (1). Entries of another version are dropped with their files when the cache opens (fixture `index-renderer-v0`). |
| Orphan files | Picture files no index entry names are removed when the cache opens. |
| Built-in presets | A pack update that changes a preset's bytes leaks the old entry the same way as an edit. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which user preset changes invalidate a thumbnail? → A: Any change that gives an imported or duplicated preset new content or takes it out of the playable list: a saved edit (PRE-015), a replacement by an archive install (FILE-003), removal (PRE-012), quarantine after a failed show, and a copy of a locked pack waiting for the unlock. They all pass through the user library's one refresh, so invalidation hangs there.
- Q: Does a rename invalidate the thumbnail? → A: No. The picture depends only on the preset's content and the renderer; a user preset's ID (`user/<random>`) survives a rename. A rename with an unchanged text keeps the thumbnail, its file and its ID, and renders nothing.
- Q: What does "exactly its thumbnail" mean? → A: Every cached entry of that preset ID whose content hash differs from the preset's current hash (all of them when the preset is gone) is removed with its file; entries of every other preset keep their file, ID and modification date.
- Q: What counts as a renderer version update? → A: The constant `rendererVersion` in the thumbnail specification, bumped by hand whenever the picture for the same preset would change: a new thumbnail size, frame count or audio, or a projectM engine pin or ANGLE update that changes drawing. The pins are not hashed into the version automatically (a pin move that changes nothing visible would throw every picture away).
- Q: When are stale entries of an older renderer version dropped? → A: When the cache opens, as PRE-001 already does: one pass over the index, before any request. That is cheaper than a check on every request, and the old files go at once.
- Q: How are orphans collected? → A: Once per launch, after the library (built-in and user presets) is listed, the cache drops every entry whose preset is no longer listed or whose hash differs from the listed one, with its file; files no entry names are removed when the cache opens (PRE-001).

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does a built-in pack preset whose bytes changed in an app update count as a changed preset? → A: Yes, through the launch collection only (PRE-002-R7): the bundled library cannot change while the app runs, so no live hook is needed for it.
- Q: Is the decoded picture held in memory for the browser dropped too? → A: Yes, the changed preset's in-memory picture is evicted with its file, so no path can show the old picture; other presets' in-memory pictures stay.
- Q: Should a changed preset that failed to draw before get another try in the same session? → A: Yes. A failure is remembered per thumbnail ID (PRE-001-R11); new content is a new ID, so it is tried once, and the old ID's remembered failure is forgotten with its entry.
- Q: Should the change be announced to VoiceOver? → A: No. Thumbnails are decorative (PRE-001-R12); the row's spoken label does not change, so nothing is announced.
- Q: Should invalidation run when the picture is not cached at all (the row was never shown)? → A: It runs and finds nothing: removing nothing is not an error and writes nothing to disk.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An edited preset shows its new picture (Priority: P1) — MVP

When I save an edit to one of my presets, its row shows a placeholder and then a picture of the new
version; every other row keeps its picture without drawing again.

**Why this priority**: It is the row's acceptance.

**Independent Test**: With a counting renderer, cache A, B and C, change B's content, browse again:
B renders once and its old file is gone; A and C render nothing and keep file, ID and modification
date.

**Acceptance Scenarios**:

1. **Given** cached thumbnails for presets A, B and C, **When** B's content changes, **Then** only B is drawn again, B's old picture is removed, and A's and C's pictures are untouched.
2. **Given** a user preset is open in the browser, **When** I save an edit with a new text, **Then** its row asks for the new picture without reopening the browser.
3. **Given** I rename a user preset without changing its text, **When** the browser lists it again, **Then** its thumbnail is kept and nothing is drawn.

### User Story 2 - A removed preset leaves nothing behind (Priority: P1)

When I remove one of my presets, its thumbnail is removed too; the others stay.

**Independent Test**: Cache A, B and C; remove B from the user library; B's file and entry are gone,
A's and C's remain.

**Acceptance Scenarios**:

1. **Given** cached thumbnails for three user presets, **When** I remove one, **Then** exactly its thumbnail file and entry are removed.
2. **Given** an entry for a preset no longer in the library (removed in an earlier launch or a pack update), **When** the app lists its library at launch, **Then** that entry and its file are removed.

### User Story 3 - A new renderer redraws every picture (Priority: P2)

After an update that changes how thumbnails are drawn, old pictures are replaced on demand.

**Independent Test**: A fixture index of renderer version 1 opened by a renderer version 2 cache:
every entry and file is dropped, and each preset renders once when requested.

**Acceptance Scenarios**:

1. **Given** a cache written by renderer version 1, **When** a version 2 build opens it, **Then** every entry is stale and dropped with its file, and each row's thumbnail is drawn again when requested.

### Edge Cases

- A render of the old content is waiting or running when the preset changes: a waiting one is cancelled; a running one finishes but its picture is not stored.
- The same preset changes twice before its row reappears: only the current content's picture is ever stored.
- A preset changes while the browser is closed: the next launch's collection, or the next refresh, removes the old picture.
- The cache folder was cleared (Clear Caches): invalidation finds nothing and does not fail.
- The index cannot be written (disk full): the removed files stay removed and the next open drops entries whose file is missing.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-002-R1**: When a preset's content changes, the cache MUST remove every entry of that preset ID whose content hash differs from the current one, together with its file, and MUST NOT touch any other preset's entry or file.
- **PRE-002-R2**: When a user preset leaves the playable list (removed, quarantined, waiting for the unlock), its entries and files MUST be removed.
- **PRE-002-R3**: A rename that keeps the content MUST keep the thumbnail (same ID and file) and render nothing.
- **PRE-002-R4**: The row of a changed preset MUST ask for its new thumbnail as soon as the browser lists the new content, without reopening the browser; the old picture MUST NOT be shown for the new content.
- **PRE-002-R5**: A waiting request for an invalidated thumbnail MUST be cancelled; a render already running MUST NOT store its picture.
- **PRE-002-R6**: Entries of another renderer version MUST be dropped with their files when the cache opens, and re-rendered on request. The renderer version is bumped by hand whenever drawing changes (thumbnail specification, engine pin or ANGLE update that changes pictures).
- **PRE-002-R7**: Once per launch, after the library is listed, entries of presets no longer listed or with a different content hash MUST be removed with their files.
- **PRE-002-R8**: Invalidation and collection MUST never fail visibly and MUST run off the main thread's critical path.
- **PRE-002-R10**: The changed or removed preset's in-memory picture MUST be evicted; other presets' in-memory pictures MUST stay. A remembered failure of a removed entry MUST be forgotten. Invalidation that finds nothing MUST write nothing.
- **PRE-002-R9**: The cache logic MUST keep building and being tested on Linux.

### Key Entities

- **Preset change**: preset ID, the content hash it had, the content hash it has now (none when removed).
- **Library listing**: preset ID → current content hash, for every preset the browser lists.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-002-S1** (acceptance): After caching A, B and C and changing B, a second pass renders exactly 1 thumbnail (B); B's old file no longer exists; A and C render 0 times and keep their file, ID and modification date.
- **PRE-002-S2**: Removing one of three user presets removes exactly 1 thumbnail file and entry; 2 remain.
- **PRE-002-S3**: A renderer version 1 fixture opened at version 2 leaves 0 entries and 0 old files; each requested preset renders once.
- **PRE-002-S4**: A rename with unchanged content renders 0 and keeps the same file.
- **PRE-002-S5**: In an app unit test, saving an edit to a user preset removes its old cached thumbnail and changes the row's request identity; another preset's thumbnail is kept.

## Assumptions

- The thumbnail cache, key, index and fake renderer of PRE-001 are reused unchanged in format (schema 1).
- No UI is added; the visible effect is the row's picture.
- The cost is a few file deletions per change and one pass over the index per launch; no device measurement is needed for this size S row.
