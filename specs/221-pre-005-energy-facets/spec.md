# Feature Specification: PRE-005 Preset Energy Facets

**Feature Branch**: `feature/pre-005` (spec directory `221-pre-005-energy-facets`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (PRE-005-T01-T16 verified on the Mac: PresetLibrary package tests on the host, the ANGLE runner test, app unit and UI tests on a private iOS 27.2 simulator; T17 threshold tuning is a `{device}` task; no ADR; the Linux build of PresetLibrary is not run on this host, it runs in CI)

**Input**: User description: "Implement PRE-005 (Preset energy facets) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Classify low, medium and high motion using deterministic frame samples."
Acceptance, verbatim: "Classification is stable for fixed preset seed and fixture." P2, depends on PRE-001."

Identifiers in this feature carry the roadmap ID: requirements `PRE-005-R1…`, success criteria `PRE-005-S1…`,
research decisions `PRE-005-D1…`, tasks `PRE-005-T01…`. Other features are cited by their own IDs: PRE-001
(thumbnail cache), PRE-002 (thumbnail invalidation), PRE-003 (tag chips), PRE-004 (colour chips), PRE-012 (user
presets), PRE-018 (integrity scanner), FILE-009/FILE-010 (storage, Clear Caches), ACC-011 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, commit `31da9491`)

| Question | Today |
|---|---|
| Pictures of presets | PRE-001 `PresetThumbnailCache`: 128 × 72 PNG thumbnails in `Library/Caches/PresetThumbnails`, drawn lazily for playable rows the user sees, one at a time. |
| How a thumbnail is drawn | ANGLE's `PresetThumbnailRunner`: a fresh engine on its own thread and context, 45 frames, each fed one block of the seeded synthetic audio (`SyntheticPCM`, seed "PRE1", 110 Hz + 440 Hz under a beat envelope, seeded noise). Only the **last** frame is read back. |
| Engine clock while drawing | **Wall clock.** The bridge never sets the engine's frame time, so a preset that moves with `time` is drawn at whatever moment 45 frames happened to take (shader compiles on the first frame can add hundreds of milliseconds). The audio is deterministic; the clock is not. |
| Engine randomness | Each engine seeds its own random numbers (`rand_start`, `rand_preset`, random textures) from the system; the public engine API offers no seed. |
| Facets in the browser | PRE-003 tag chips and PRE-004 colour chips (learned from thumbnails on the row's decode task, `Library/Caches/PresetColors/colors.json`), combined with AND, Favorites and search into `filteredListing`. |
| Motion | **None.** Nothing knows how much a preset moves. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where do the frame samples come from? → A: From the PRE-001 thumbnail drawing itself: besides its final frame, it reads back two earlier frames of the same drawing (three samples, four frames apart, at fixed points of the fixed 45-frame run). Nothing is rendered just to learn motion, nothing runs at build time or at launch, and the extra cost is two small read-backs per thumbnail.
- Q: What makes the samples deterministic? → A: The same synthetic audio as the thumbnail (fixed seed), fixed frame positions, and an engine clock pinned to the frame number (frame n is drawn at n/60 s) instead of the wall clock. The score is integer arithmetic on a fixed grid, so the same three frames always give the bit-identical score on every platform.
- Q: How is motion measured and classified? → A: The mean absolute brightness change between consecutive samples on a fixed 32 × 18 grid, averaged over the two pairs, in thousandths of a brightness level (0-255 scale). Below 4 levels is Calm (low motion), below 16 is Moderate (medium), 16 and above is Energetic (high). The thresholds are provisional until a device sweep tunes them; changing them needs no stored data to change.
- Q: Where is the motion kept? → A: In two places that share the thumbnail's lifetime: the score is written into the thumbnail picture itself (a small text field of the PNG), and the browser's index `Library/Caches/PresetMotion/motion.json` (versioned, rebuildable, excluded from backup, emptied by Clear Caches) holds preset ID → thumbnail ID and score so the chips can count without decoding pictures. A damaged index is relearned from the pictures as rows are shown.
- Q: How do the energy chips combine with other filters? → A: The three classes exclude each other, so selected energy chips combine with OR among themselves (Calm or Moderate) and with AND against tags, colours, Favorites and search. Selections are in memory only.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Must every cached thumbnail be redrawn so it gets a score (a renderer version bump)? → A: No. Pinning the clock makes the drawing match what PRE-001-D2 already describes (45 frames at 60 fps); thumbnails cached by earlier builds exist only in unreleased development builds, so bumping the version (and redrawing every cached picture, and rewriting PRE-001's version fixtures) costs more than it gives. Such a picture simply has no score; it gets one when it is drawn again.
- Q: What does the list show when only energy chips are selected? → A: PRE-004's filtered list (alphabetical across packs, locked presets marked by their rows) now driven by tags AND colours AND energy, with "No presets match these filters" when empty.
- Q: What do the chip counts count? → A: Listed presets whose current score falls in the class, independent of the other selections (like PRE-003 and PRE-004). Only classes with a count above zero get a chip, in the order Calm, Moderate, Energetic; a caption says how many presets have a class.
- Q: Does a preset row show or say its class? → A: No, as with colours: the chips carry the names; 12,847 longer row labels would gain little.
- Q: When is the index written? → A: As PRE-004: one second after the first unsaved score (coalescing delay injected for tests), atomically; nothing extra at backgrounding, since an unwritten score is learned again from the cached picture.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find calm or energetic presets (Priority: P1) — MVP

While browsing presets, I see "Calm", "Moderate" and "Energetic" chips with how many presets are in each. Choosing
Calm lists exactly the presets whose pictures barely move; choosing a colour, a tag or typing a search narrows
that further.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: Seeded synthetic frame sequences with known motion (static, slow drift, fast noise) are
scored and classified; the energy filter returns exactly the fixture presets of the chosen class.

**Acceptance Scenarios**:

1. **Given** presets whose thumbnails have been made, **When** I open the browser, **Then** an energy chip row shows the classes present with a count each.
2. **Given** the energy chips, **When** I choose Calm, **Then** the list shows exactly the presets classified Calm, alphabetically, and VoiceOver announces the count.
3. **Given** Calm is chosen, **When** I also choose Energetic, **Then** presets of either class are listed; **When** I choose a colour or a tag or type a search, **Then** only presets matching it as well remain; Clear removes the energy selection.

### User Story 2 - The same preset always gets the same class (Priority: P1)

**Why this priority**: It is the row's acceptance ("Classification is stable for fixed preset seed and fixture").

**Independent Test**: Scoring the same fixture frames twice gives bit-identical scores equal to pinned values;
drawing the same preset twice with the real engine gives identical samples.

**Acceptance Scenarios**:

1. **Given** a fixed fixture (frames and seed), **When** it is scored any number of times, on any platform, **Then** the score is the same number and the class the same.
2. **Given** a preset that moves with time, **When** its thumbnail samples are drawn twice, **Then** the samples are identical (the clock is pinned).

### User Story 3 - A damaged or old motion index rebuilds itself (Priority: P2)

**Independent Test**: Fixture index files (version 0, an unknown newer version, corrupt bytes, an older score
version, the current version) open without error: all but the current one start empty and are rewritten; the
current one keeps its valid entries.

**Acceptance Scenarios**:

1. **Given** an index from an older or unknown schema, another score version, or unreadable bytes, **When** it opens, **Then** it is rebuilt empty, saved in the current schema, and motion is relearned from the pictures.
2. **Given** an index in the current schema, **When** it opens, **Then** its entries are kept; entries with a negative score or no thumbnail ID are dropped.

### Edge Cases

- A thumbnail cached by an earlier build has no motion field: that preset has no class until its thumbnail is drawn again (Clear Caches, a preset edit, or a renderer version change); the chip row says how many presets have a class.
- A preset's content changes (PRE-002): its old score stops counting and is learned again from the new thumbnail.
- A preset leaves the library (PRE-012 delete, PRE-018 prune): its score is dropped at the next launch's collection.
- Clear Caches removes the index with the thumbnails; scores in memory stay until relaunch.
- A drawing that fails or is stopped gives no picture and no score.
- A preset whose motion depends on the engine's own random numbers can score differently between drawings; the class only changes when the score sits near a threshold. This is a documented limit of the public engine API.
- No preset has a class yet: the energy chip row is hidden.
- A selected class that no preset has any more stays selected but lists nothing ("No presets match these filters").

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-005-R1**: The thumbnail drawing MUST read back three frame samples at fixed positions of its fixed run (the last one is the thumbnail), with the engine clock pinned to the frame number and the thumbnail's seeded synthetic audio; nothing MUST be drawn only to learn motion.
- **PRE-005-R2**: The motion score MUST be computed from the samples with deterministic integer arithmetic on a fixed grid independent of the picture size: the mean absolute brightness change between consecutive samples, averaged over the pairs, in thousandths of a level.
- **PRE-005-R3**: Each score MUST map to exactly one class: Calm (below 4 levels), Moderate (below 16), Energetic (16 and above).
- **PRE-005-R4**: The score MUST travel with the thumbnail picture (a versioned text field in the PNG) and be learned from it off the main thread on the row's existing decode, never at build time or launch.
- **PRE-005-R5**: Scores MUST be stored per preset in a versioned local JSON index (schema version and score version), keyed by preset ID and tied to the thumbnail's stable ID; an entry whose thumbnail ID is not the preset's current one MUST NOT count.
- **PRE-005-R6**: Opening the index MUST never fail: a missing file gives an empty index; unreadable bytes, any other schema (older such as 0, newer or unknown) or another score version MUST give an empty index saved in the current schema; a current index MUST be kept, dropping only invalid entries.
- **PRE-005-R7**: Index writes MUST be coalesced (at most one per second while scores arrive) and atomic.
- **PRE-005-R8**: The browser MUST show an energy chip row (Calm, Moderate, Energetic; each with its count) when at least one listed preset has a class, under the colour chips on the home and above search results.
- **PRE-005-R9**: Selected energy chips MUST combine with OR among themselves and with AND against the selected tags, colours, Favorites and the search text; the filtered list MUST contain exactly the listed presets matching all of them, alphabetical across packs.
- **PRE-005-R10**: Chips MUST be accessible by name: label "<Class> motion", value = count, Selected trait when chosen; a chip change MUST announce the result count on the search lane (ACC-011), never a direct post.
- **PRE-005-R11**: The motion index MUST follow the thumbnails' lifecycle: PRE-002 invalidation drops a changed preset's score, the launch collection drops presets no longer listed, Clear Caches removes the file.
- **PRE-005-R12**: The energy selection MUST NOT become a stored scope (as PRE-004-R11).
- **PRE-005-R13**: The score, classes, PNG field, index and filter MUST be plain Swift that builds and is tested on Linux.

### Key Entities

- **PresetEnergy**: Calm, Moderate or Energetic, with a spoken name.
- **PresetMotionScore**: the deterministic scorer from RGBA frame samples to a score and its class.
- **PresetMotionPNG**: writes and reads the score's text field in a thumbnail PNG.
- **PresetMotionIndex** / **PresetMotionStore**: the versioned JSON index with open-time repair, and the actor that records scores and coalesces writes.
- **PresetEnergyFilter**: preset IDs in any selected class; per-class counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-005-S1**: Seeded synthetic fixtures (static, slow drift, fast noise) classify as Calm, Moderate and Energetic; scoring each twice gives bit-identical scores equal to pinned values; the energy filter returns exactly the fixture presets of each class and of a two-class selection (package test, runs on Linux).
- **PRE-005-S2**: Index migration fixtures: version 0, an unknown version (99), corrupt bytes and an older score version open as rebuilt; the current version keeps its valid entries (package test).
- **PRE-005-S3**: With the real engine on a simulator, drawing a time-driven preset twice gives identical samples and an identical score (ANGLERendering test; simulator, not device evidence).
- **PRE-005-S4**: Through the real thumbnail model, a produced thumbnail records its class once and the coordinator's energy filter lists it, combined with a colour narrows it (app unit test on the simulator).
- **PRE-005-S5**: In the app on a simulator, energy chips appear after thumbnails are made, choosing one lists only matching presets, and Clear restores the home (UI test under 30 s).

## Assumptions

- The class describes the PRE-001 still run (deterministic audio and clock), not every moment of a preset.
- Coverage grows with browsing, like colours; classifying the whole library would mean rendering it all, which PRE-001 rejected.
- No new UserDefaults key: the energy selection is in memory only.
- The thresholds are provisional; tuning them on devices is a `{device}` follow-up, and a threshold change needs no data migration because the score, not the class, is stored.
