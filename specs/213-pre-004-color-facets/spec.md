# Feature Specification: PRE-004 Preset Color Facets

**Feature Branch**: `feature/pre-004` (spec directory `213-pre-004-color-facets`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PRE-004 (Preset color facets) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Index dominant palette colors for local filtering." Acceptance, verbatim:
"Palette filter matches seeded thumbnail color fixtures." Verification: unit + simulator + fixture migrations.
P2, size M, depends on PRE-001."

Identifiers in this feature carry the roadmap ID: requirements `PRE-004-R1…`, success criteria `PRE-004-S1…`,
research decisions `PRE-004-D1…`, tasks `PRE-004-T01…`. Other features are cited by their own IDs: PRE-001
(thumbnail cache), PRE-002 (thumbnail invalidation), PRE-003 (tag chips), PRE-012 (user presets), PRE-018
(integrity scanner), FILE-009/FILE-010 (storage, Clear Caches), ACC-004/ACC-011 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, commit `691547a1`)

| Question | Today |
|---|---|
| Pictures of presets | PRE-001 `PresetThumbnailCache` (PresetLibrary, Foundation only): 128 × 72 PNG thumbnails in `Library/Caches/PresetThumbnails`, a versioned `index.json` repaired on open, stable IDs from preset ID + content hash + renderer version. Generated lazily, only for playable rows the user sees, one at a time at utility priority. |
| Thumbnails at build time | **None.** The build phase indexes and archives the 12,847 preset files only; a picture needs the ANGLE engine and seconds of GPU time per preset, so the build cannot make them. |
| Decoding | The app decodes thumbnail PNGs with `UIImage(data:)` on a detached utility task (`PresetThumbnailModel.image`); the renderer encodes RGBA8 rows with ImageIO (`PNGThumbnailEncoder`). |
| Filters in the browser | PRE-003 tag chips (AND, in memory) under the All/Favorites picker and above search results; selected chips replace the home with `TaggedPresetList`; search is narrowed by `within:`. Favorites narrows the tagged list. |
| Invalidation | PRE-002: a changed user preset (PRE-012/PRE-015 edit) invalidates its old thumbnails; at launch `retainOnly` drops entries of presets not listed or listed with another hash. PRE-018 prunes favorites, tags and thumbnails of removed presets through the same paths. |
| Colors | **None.** No preset has a colour anywhere. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where do a preset's colours come from? → A: From its PRE-001 thumbnail, the moment that thumbnail is drawn or read back from the cache for a row. Nothing runs at build time (the build has no renderer) or at launch, and nothing is rendered just to learn colours. A preset that has never had a thumbnail has no colours yet; the colour chips count and filter only presets with colours, and the chip row says how many presets have colours so far.
- Q: Which colours can a preset have? → A: Eleven named colour families: Red, Orange, Yellow, Green, Cyan, Blue, Purple, Pink, White, Grey and Black. Each sampled pixel falls into exactly one family by its hue, lightness and saturation; the names are what chips and VoiceOver say, never the colour alone.
- Q: What makes a colour "dominant"? → A: The share of sampled pixels in a family. A preset's dominant colours are the families with at least 12% of the samples, largest share first (ties in the family order above), at most three. A picture where no family reaches 12% keeps its single largest family.
- Q: Where is the colour index kept? → A: In `Library/Caches/PresetColors/colors.json`, a versioned JSON file next to the thumbnails, excluded from backup. It is rebuildable from the thumbnails, so it is counted in Storage's "Caches", emptied by Clear Caches (FILE-010) and is not a FILE-011 erase category.
- Q: How do the colour chips combine with other filters? → A: Selected colour chips combine with AND (a preset must have every selected colour among its dominant colours), and with the selected tags, Favorites and the search text, all at once. Selections are in memory only, like the tag chips.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: What does the list show when only colour chips are selected? → A: The same filtered list the tag chips use (alphabetical across packs, locked presets marked by their rows), now driven by tags AND colours; its empty text becomes "No presets match these filters" whenever a colour is selected (the PRE-003 text stays for tags alone).
- Q: What do the chip counts count? → A: Listed presets (built-in and playable user presets) whose current dominant colours include the family, independent of the other selections, like the PRE-003 tag counts. Only families with a count above zero get a chip, in the fixed family order.
- Q: Does a preset row show or say its colours? → A: No. The row stays as PRE-001/PRE-003 left it; colours are a filter, and adding them to every row's VoiceOver label would lengthen 12,847 labels for little gain. The chips carry the names.
- Q: When is the index written? → A: After the first new colour, at most once per second (a coalescing delay injected for tests), atomically; and once more when the app goes to the background is not needed, because an unwritten colour is simply learned again from the cached thumbnail.
- Q: Is a cached thumbnail read again just to learn its colours? → A: Only when its row asks for the picture anyway (the row's existing decode path); the colours are computed from the same decoded pixels on the same utility task, so no extra file read happens.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find presets by colour (Priority: P1) — MVP

While browsing presets, I see colour chips (Red, Blue, …) with how many presets have each colour. Choosing
Blue lists exactly the presets whose pictures are mostly blue; choosing a tag or typing a search narrows that
further.

**Why this priority**: It is the row's observable behavior and its acceptance ("Palette filter matches seeded
thumbnail color fixtures").

**Independent Test**: Seeded synthetic thumbnails (solid, two-tone, gradient, noisy) are indexed; filtering by
each colour family returns exactly the fixture presets whose dominant colours include it.

**Acceptance Scenarios**:

1. **Given** presets whose thumbnails have been made, **When** I open the browser, **Then** a colour chip row shows the families present with a count each.
2. **Given** the colour chips, **When** I choose Blue, **Then** the list shows exactly the presets whose dominant colours include Blue, alphabetically, and VoiceOver announces the count.
3. **Given** Blue is chosen, **When** I also choose a tag or type a search, **Then** only presets matching all of them are shown; Clear removes the colour selection.

### User Story 2 - Colours appear as I browse, without slowing anything (Priority: P1)

Colours are learned in the background from thumbnails as they are drawn or shown; scrolling and the visualizer
are not slowed, and the app does no extra work at launch.

**Independent Test**: A thumbnail produced through the cache records its colours once; a cached thumbnail
without colours is indexed when its row asks again; nothing is indexed for a locked preset.

**Acceptance Scenarios**:

1. **Given** a preset without colours, **When** its row's thumbnail is drawn or read from the cache, **Then** its colours are computed off the main thread and its chip counts update.
2. **Given** colours already indexed, **When** the app is relaunched, **Then** they are read back without recomputing.

### User Story 3 - A damaged or old colour index rebuilds itself (Priority: P2)

**Independent Test**: Fixture index files (version 0, an unknown newer version, corrupt bytes, an older
palette version, the current version) open without error: all but the current one start empty and are
rewritten; the current one keeps its entries.

**Acceptance Scenarios**:

1. **Given** an index from an older or unknown schema, or unreadable bytes, **When** it opens, **Then** it is rebuilt empty and saved in the current schema, and colours are learned again from thumbnails.
2. **Given** an index in the current schema, **When** it opens, **Then** its entries are kept; entries naming unknown colours are dropped.

### Edge Cases

- A preset's content changes (PRE-002): its old colours stop counting (they belonged to the old thumbnail ID) and are learned again from the new thumbnail.
- A preset leaves the library (PRE-012 delete, PRE-018 prune): its colours are dropped at the next launch's collection with the thumbnails.
- Clear Caches removes the colour file; colours already in memory stay until relaunch (they still describe the same presets), then are learned again.
- The renderer version changes: every thumbnail ID changes, so every colour is learned again.
- A thumbnail that cannot be decoded gives no colours; the row keeps working.
- No preset has colours yet: the colour chip row is hidden.
- A selected colour that no preset has any more stays selected but lists nothing ("No presets match these filters").
- Disk full: the colour file cannot be written; colours stay in memory for the session.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-004-R1**: The system MUST classify each sampled pixel of a thumbnail into exactly one of eleven named colour families (Red, Orange, Yellow, Green, Cyan, Blue, Purple, Pink, White, Grey, Black) with fixed, deterministic rules.
- **PRE-004-R2**: The system MUST sample a fixed grid of the thumbnail (independent of its pixel size) and report as dominant the families with at least 12% of the samples, largest first, at most three, and at least one.
- **PRE-004-R3**: Colours MUST be computed only from a thumbnail produced or read by the PRE-001 cache, off the main thread, never at build time or launch, and never by rendering a preset just for colours.
- **PRE-004-R4**: Colours MUST be stored per preset in a versioned local JSON index (schema version and palette version), keyed by preset ID and tied to the thumbnail's stable ID; an entry whose thumbnail ID is not the preset's current one MUST NOT count.
- **PRE-004-R5**: Opening the index MUST never fail: a missing file gives an empty index; unreadable bytes, any schema other than the current one (older such as 0, newer or unknown) or another palette version MUST give an empty index that is saved in the current schema; a current index MUST be kept, dropping only entries with unknown colour names.
- **PRE-004-R6**: Index writes MUST be coalesced (at most one write per second while colours are being learned) and atomic.
- **PRE-004-R7**: The browser MUST show a colour chip row (each chip: a decorative swatch, the family's name, the count of presets with that colour) when at least one listed preset has colours, under the tag chips on the home and above search results.
- **PRE-004-R8**: Selected colour chips MUST combine with AND among themselves and with the selected tags, Favorites and the search text; the filtered list MUST contain exactly the listed presets matching all of them, alphabetical across packs.
- **PRE-004-R9**: Chips MUST be accessible by name: label = family name, value = count, Selected trait when chosen; a chip change MUST announce the result count on the search lane (ACC-011), never a direct post.
- **PRE-004-R10**: The colour index MUST follow the thumbnails' lifecycle: PRE-002 invalidation drops a changed preset's colours, the launch collection drops presets no longer listed, and Clear Caches removes the file.
- **PRE-004-R11**: The colour selection MUST NOT become a stored scope: choosing a preset from a colour-filtered list uses the tag scope when tags are selected, otherwise All presets.
- **PRE-004-R12**: Decoding MUST stay behind Apple-only guards in PresetLibrary; the classification, ranking, index and filter MUST be plain Swift that builds and is tested on Linux.

### Key Entities

- **PresetColorFamily**: one of the eleven named families, with a spoken name and a display swatch.
- **PresetColorPalette**: the deterministic sampler and ranker from RGBA pixels to dominant families.
- **PresetColorIndex**: the versioned JSON index (schema version, palette version, preset ID → thumbnail ID and families) with its open-time repair.
- **PresetColorStore**: the actor that owns the index file, records colours and coalesces writes.
- **PresetColorFilter**: preset IDs matching all selected families; per-family counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-004-S1**: Seeded synthetic thumbnails (solid red, two-tone blue/yellow, a black-to-white grey gradient, a noisy green) map to their expected dominant families, and the palette filter returns exactly the fixture presets whose dominant colours include the chosen family, for every family (package test, runs on Linux).
- **PRE-004-S2**: Index migration fixtures: version 0, an unknown version (99), corrupt bytes and an older palette version open as rebuilt (empty, rewritten in the current schema); the current version keeps its entries (package test).
- **PRE-004-S3**: Through the real thumbnail model with a fixture renderer, a produced thumbnail records its colours once and the coordinator's colour filter lists it (app unit test on the simulator).
- **PRE-004-S4**: In the app on a simulator, colour chips appear after thumbnails are made, choosing one lists only matching presets, and Clear restores the home (UI test under 30 s).
- **PRE-004-S5**: Indexing one thumbnail takes under 5 ms on the host in Debug (sampling 576 pixels), so it adds nothing visible to a thumbnail's ~1 s render.

## Assumptions

- Colours describe the PRE-001 still frame (deterministic audio, fixed seed), not every moment of a preset; that is what the user sees in the row.
- Coverage grows with browsing; indexing the whole 12,847-preset library would need rendering it all, which PRE-001 rejected for battery and GPU cost.
- No new UserDefaults key: the colour selection is in memory only.
