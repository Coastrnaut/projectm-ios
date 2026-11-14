# Feature Specification: PERF-005 Preset prewarm scheduler

**Feature Branch**: `feature/perf-005` (spec directory `179-perf-005-prewarm-scheduler`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-005 (Preset prewarm scheduler) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Prioritize next likely scene assets without blocking active frame." Acceptance,
verbatim: "Queue cancellation releases stale work and respects memory budget." P1, size M, depends on SHOW-001."

Identifiers carry the roadmap ID: requirements `PERF-005-R1…`, success criteria `PERF-005-S1…`, tasks
`PERF-005-T01…`. Other features are cited by their own IDs: SC-104 (feature 002 preset switch time and the
`PresetPrewarmer`), SHOW-001 (show cue list), PERF-011 (presentation suspension), PERF-003 (adaptive quality and
its thermal inputs), PERF-006 (memory pressure recovery), MED-001 (photo layer), MED-002 (video layer), MED-006
(image slideshow), MED-010 (logo), PRE-001 (thumbnails), PRE-010 (audition), SCN-006 (scene previews), SCN-008
(scene snapshots and `MediaLoadSpy`).

## Baseline: what exists today (audit of 2026-11-14, commit `6b32708e`)

| Area | Today |
|---|---|
| Preset warm-up (SC-104) | `PresetCoordinator.planUpcoming()` picks the next Random pick and the next preset in the scope after every switch and calls `AppCoordinator.prewarm` → `ANGLERenderer.prewarm` → `PresetWarmUpController` (2.5 s delay after the switch, a newer request replaces an older one, suspended under PERF-011, two PERF-006 steps) → `PresetPrewarmer` (own thread, utility priority, own EGL context and engine, renders each preset twice into a 256 px target; warmed IDs are remembered). It knows nothing about the show. |
| Audition (PRE-010) | A trial engine renders a preset in a preview; it does not warm anything. |
| Thumbnails (PRE-001) | `PresetThumbnailRunner`: a bounded, cancellable, newest-first queue of preset renders. The pattern this feature follows for its queue. |
| Show (SHOW-001) | `ShowCoordinator` steps a `ShowCueList` (Next, Previous, Go to Cue; no wrap). Stepping reads the cue's scene from disk, validates it and applies it. Nothing looks ahead to the next cue. |
| Photo layer (MED-001, MED-006) | `ImageLayerSource.content = .file(url)` reads, decodes and uploads the picture on a background queue (the shown frame is transparent meanwhile). `preload(url)` fills a one-entry prepared slot that the slideshow uses for its next slide. The Photo visual (`PhotoVisualHost`) exists only while Photo is the visual, so a cue that switches from another visual to a photo scene always decodes from scratch, and a decoded picture is lost whenever the visual changes. |
| Video (MED-002), logo (MED-010) | The video layer opens its asset reader when it is shown; the logo layer decodes its picture when attached. |
| Scene previews (SCN-006) | Captured pictures of applied scenes; not an input of the warm-up. |
| Suspension (PERF-011), thermal (PERF-003, FR-049) | Presentation-bound resources are suspended while the app cannot present. `QualityGovernor` reads the thermal state and Low Power; PERF-003's ladder reduces the glow at the serious state. |

The gap: the next cue's media is decoded only when the cue is applied, so stepping to a photo scene shows a
transparent frame while its picture loads, and nothing bounds or cancels look-ahead work as a whole.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What does the scheduler warm? → A: The media of the scenes of the next cue and the cue after it (photo layer content: the scene's slideshow first slide, else the stored photo), and the next preset picks (Random and Next). Preset picks keep going through the existing `PresetWarmUpController`/`PresetPrewarmer` unchanged, with the 2.5 s delay.
- Q: Are video assets and the logo warmed? → A: Not in this feature. The plan model has kinds for them and orders them, but the app's loader skips them: opening a video asset reader ahead holds a hardware decoder session for a video that may never be shown, and the logo is small (its decode is not what delays a cue). Recorded as a follow-up, not a gap in the acceptance.
- Q: What is the memory budget? → A: Bytes of decoded media held by the prewarm cache, by device class from physical memory: under 4 GB → 48 MB, 4 GB to under 8 GB → 96 MB, 8 GB or more → 192 MB. (A 4032 × 3024 photo with its mip chain is about 65 MB, so one typical photo fits on every class.) An item larger than the budget is not kept.
- Q: Which cache entries are evicted first? → A: Entries the live scene uses are never evicted. Among the others, only entries no more important than the incoming item are candidates (a next-cue entry is never evicted to make room for a later cue's item), least recently used first. If not enough can be evicted, the incoming item is dropped.
- Q: When is work paused? → A: While the app cannot present (PERF-011) and while the thermal state is serious or critical (the PERF-003 signal). Low Power limits look-ahead to the next cue. A memory pressure signal (PERF-006, cache tier) releases the whole prewarm cache.
- Q: When does media work start after a step? → A: After a settle delay of 0.5 s on an injected clock, so the step's own apply and the start of its transition come first; presets keep their own 2.5 s.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The next cue's picture is ready when the performer steps (Priority: P1)

A performer runs a show whose cue 2 is a photo scene while cue 1 is a spectrum. While cue 1 plays, the app
decodes cue 2's picture in the background. Stepping to cue 2 shows the picture on the first frame, with no
transparent loading frame and no second decode.

**Why this priority**: The roadmap row's observable behaviour.

**Independent Test**: An app test steps a show A (spectrum) → B (photo): B's photo is decoded exactly once while
A is active, and applying B adopts that decoded picture (the photo layer starts no load of its own).

**Acceptance Scenarios**:

1. **Given** cue A active and cue B a photo scene, **When** the settle delay passes, **Then** B's picture is decoded once in the background and held by the prewarm cache.
2. **Given** B's picture is prewarmed, **When** the performer steps to B, **Then** the photo layer is ready at once with that picture and no further decode happens.

### User Story 2 - Stale work is cancelled and its memory released (Priority: P1)

The performer jumps from cue A straight to cue C while B's picture is being prewarmed. B's queued and in-flight
work is cancelled and everything it decoded is released, while held prewarmed bytes never exceed the budget and
the live scene's pictures are never evicted.

**Why this priority**: The roadmap row's acceptance.

**Independent Test**: With heavy fake assets of known sizes and a counter of live decoded buffers, plan A → B → C,
jump to C mid-prewarm: B's queued item never starts, its in-flight item's result is dropped, and the counter
returns to its baseline; an eviction-order test keeps held bytes within the budget and never evicts a live asset.

**Acceptance Scenarios**:

1. **Given** B's items queued and one in flight, **When** the plan changes to C's, **Then** B's queued items are removed, the in-flight item is cancelled, and its buffer is released when it returns.
2. **Given** a budget, **When** items of known sizes are admitted, **Then** held bytes never exceed the budget, entries are evicted least recently used first among entries no more important than the new one, and an item larger than the budget is not kept.
3. **Given** the live scene's assets in the cache, **When** eviction runs, **Then** they are never evicted.

### User Story 3 - Prewarming never costs the live frame (Priority: P1)

Prewarming never runs on the main thread, never runs while the app cannot present or the device is hot, and the
existing preset warm-up keeps its timing.

**Acceptance Scenarios**:

1. **Given** any plan, **When** items load, **Then** every load runs on the scheduler's background executor, never on the main thread.
2. **Given** the app cannot present, **When** a plan arrives, **Then** nothing starts until presentation returns; a suspension cancels the in-flight item before its graphics step and waits for a running graphics step to end.
3. **Given** a serious or critical thermal state, **When** a plan arrives, **Then** nothing starts until the state is nominal or fair again.
4. **Given** preset picks, **When** they are planned, **Then** they are handed to the existing preset warm-up at once, which still waits its own 2.5 s.

### Edge Cases

- The plan contains an item already cached: it is kept and not decoded again (its recency is refreshed).
- A cached item that the new plan no longer names and the live scene does not use is released at once.
- An item that fails to load is not retried for this plan; the step that later shows it decodes it as today.
- The last cue is active: the plan has no cue items (no wrap); preset picks still pass through.
- The show is in standby: the next cue is cue 1.
- A cue's scene cannot be read: it contributes nothing to the plan.
- The scheduler is shut down: queued items are dropped and every held entry is released.

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-005-R1**: A plan MUST list the items to prewarm in priority order: the next cue's media first, then the media of the cue after it; preset picks are a separate list. Each item has a key (kind and identifier), a rank (0 = next cue, 1 = the one after) and a URL or identifier the loader understands.
- **PERF-005-R2**: Replacing the plan MUST cancel stale work: queued items the new plan does not name are removed; an in-flight item the new plan does not name is marked cancelled, and its result is released when it returns instead of being cached; cached entries the new plan does not name and the live scene does not use are released.
- **PERF-005-R3**: Bytes held by the prewarm cache MUST never exceed the budget. The budget MUST be chosen by device class (R-D3 values) and be injectable. Admission evicts per the Clarifications order; an item larger than the budget, or that cannot fit, is released at once.
- **PERF-005-R4**: Entries named as the live scene's assets MUST never be evicted or released by replanning; taking an entry for the live scene removes it from the prewarm accounting.
- **PERF-005-R5**: Every load MUST run on an injected executor (by default a serial background queue at utility priority), one item at a time, never on the main thread.
- **PERF-005-R6**: Work MUST be paused while any pause reason holds (presentation lost, thermal serious or critical, explicit): nothing new starts. A presentation suspension MUST cancel the in-flight item before its graphics step and MUST return only when no graphics step is running.
- **PERF-005-R7**: Media work MUST start a settle delay (0.5 s by default) after a plan, measured on an injected clock; a newer plan restarts the delay.
- **PERF-005-R8**: Preset picks MUST be forwarded to the existing preset warm-up synchronously and unchanged; its 2.5 s delay, suspension and memory steps are unchanged, and the scheduler adds no delay of its own.
- **PERF-005-R9**: Under Low Power, the plan MUST be cut to rank 0 (the next cue).
- **PERF-005-R10**: A PERF-006 cache-tier responder MUST release the whole prewarm cache (reporting the bytes) and cancel the in-flight item.
- **PERF-005-R11**: The photo layer MUST be able to adopt a prewarmed picture when its content is set to that picture's URL: the layer becomes ready at once and starts no load of its own.
- **PERF-005-R12**: In the app, stepping the show (Next, Previous, Go to Cue, a scene jump) and every preset switch MUST replan; the live scene's photo URL is the live key.
- **PERF-005-R13**: The scheduler's core MUST be plain Swift with injected executor, clock, budget and loader, testable on Linux.

### Key Entities

- **Prewarm item**: key (kind: photo, video, logo; identifier), rank, source URL.
- **Prewarm plan**: ordered media items, preset picks, live keys.
- **Prewarmed asset**: the loaded payload and its byte count.
- **Prewarm cache**: entries with bytes, rank and recency, within the budget.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-005-S1**: After a jump from A to C mid-prewarm, B's work is cancelled and the count of live decoded buffers returns to its baseline (acceptance test).
- **PERF-005-S2**: Across an admission sequence of known sizes, held bytes never exceed the budget, the eviction order matches the rule, and live assets are never evicted (eviction-order test).
- **PERF-005-S3**: Zero loads run on the main thread (executor spy).
- **PERF-005-S4**: Zero loads start while suspended or under thermal pressure.
- **PERF-005-S5**: Stepping to a prewarmed photo scene decodes its picture exactly once in total (app test).
- **PERF-005-S6**: The preset warm-up's request reaches the existing controller at the same moment as before (no added delay) and its 2.5 s delay is unchanged.

## Assumptions

- Simulator results are not performance evidence; frame-rate effects on devices are a `{device}` task.
- One stored photo plus slideshow slides are the photo sources a scene can name (MED-001, MED-006).
- The Metal device used for prewarmed textures is the system default device, the one every photo layer uses.
