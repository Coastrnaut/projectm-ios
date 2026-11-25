# Feature Specification: PRE-009 Preset Comparison

**Feature Branch**: `feature/pre-009` (spec directory `235-pre-009-preset-comparison`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (PRE-009-T01-T12, T14 verified on the Mac: Rendering and ANGLERendering package tests, app unit and UI tests on the private simulator "PRE9 iPhone 17", iOS 27.2; no ADR; T13 (S5, D1 GPU and thermal cost) is open `{device}`)

**Input**: User description: "Implement PRE-009 (Preset comparison) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Preview two presets side by side using shared PCM input."
Acceptance, verbatim: "Both previews respond to identical sample timestamps." P2, effort L, depends on PRE-001."

Identifiers in this feature carry the roadmap ID: requirements `PRE-009-R1…`, success criteria `PRE-009-S1…`,
research decisions `PRE-009-D1…`, tasks `PRE-009-T01…`. Other features are cited by their own IDs: PRE-001
(thumbnails, off-screen drawing), PRE-005 (pinned engine clock), PRE-010 (quick audition), PRE-012 (user presets
and their trial), ACC-002 (flagged presets), ACC-012 (sensory safety clamp), FX-019 (flash envelope), PERF-006
(memory pressure), PERF-008 (quality governor), PERF-011 (presentation suspension), AUD-013 (latency offset).

## Baseline: what exists today (audit of 2026-11-14, commit `4249a00b`)

| Question | Today |
|---|---|
| Live audio to projectM | `ANGLERenderer` (main thread, CADisplayLink up to 60 fps) reads its attached `NormalizedPCMReader` once per frame (`latencyOffset.rendererDelayed(manager.normalizedOutput)`, AUD-013) and calls `addPCMInterleavedStereo`. The ring is single-producer single-consumer: the renderer on the main thread is its only reader. |
| Engine clock | PRE-005 added `ProjectMEngine.setFrameTime(_:)` (`projectm_set_frame_time`); thumbnails pin frame n at n/60 s. The visible engine runs on the wall clock. |
| Second engines | `PresetPrewarmer` (warm-up), `PresetTrialRunner` (PRE-012 trial) and `PresetThumbnailRunner` (PRE-001) each run on their own thread with an unshared EGL context on the renderer's display, a fresh engine and a BGRA8 target; all stop while the app cannot present (PERF-011). |
| Flash safety | FX-019's `CFlashLimiter` pass (`PMFlashLimiterBegin/Finish`, any target framebuffer) and the envelope from `SafetyClamp` (`flashLimitsOverride ?? forReduceFlashing(reducesFlashing)`). |
| Browser | PRE-001 thumbnails (still pictures), PRE-010 "Preview" (loads one preset on the main screen with Keep/Cancel). |
| Side-by-side live previews | **None.** No view shows two presets moving at once. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: How does the user start a comparison? → A: From the preset browser: every row that may be previewed (PRE-010's rule: playable, not flagged under Reduce flashing) offers "Compare…" (touch-and-hold menu and a VoiceOver action). The first choice becomes A and a bar at the bottom of the browser says "Compare <A>: choose a second preset" with Cancel; while A waits, the rows offer "Compare with <A>". Choosing a different preset as B opens the Compare sheet. Tapping a row still plays it (no hidden mode).
- Q: What does the Compare sheet show? → A: Two live previews labelled A and B with the preset names, side by side when the sheet is wider than tall and stacked otherwise (iPhone portrait), each with a "Play A"/"Play B" button, plus Close. Playing one closes the sheet and the browser exactly as choosing that row would (the list it was picked from becomes the scope, FR-116; ACC-002's warning and PRE-012's guard apply as usual).
- Q: What is "shared PCM input"? → A: One timeline drives both previews. On each tick the app reads one block of the live input once, stamps it with the tick's frame time (tick n at n / preview rate seconds since the comparison started) and its sample range (first sample index, count), and both engines receive that same block and that same frame time before drawing. Neither engine reads audio on its own.
- Q: What happens when there is no live audio (no source running)? → A: The tick carries a quiet, deterministic test signal instead (the PRE-001 thumbnail signal), still one block shared by both, so the previews move. The sheet says "No audio playing: showing a test signal" so nothing claims a source works (Constitution: no compatibility claims).
- Q: What if one preview is slower to draw? → A: The two never drift. Both engines are fed and drawn on one worker in lockstep (A then B for each block); while the worker is busy, new ticks wait in a short queue, and the worker takes all waiting ticks at once as one batch (their blocks joined in order, the last tick's frame time). Both engines receive the identical batch, so a slow preview makes both drop display frames together and both catch up together. When more than 6 ticks (0.2 s at 30 fps) wait, the oldest are dropped before either engine sees them.
- Q: Does the main visual keep running? → A: No: it pauses while the Compare sheet is open and resumes when it closes. The sheet covers it, the comparison becomes the live input's only reader, and the GPU budget goes to the two previews.
- Q: How large and how fast are the previews? → A: Each draws at 320 × 180 pixels at 30 frames per second (15 under Low Power Mode or a serious thermal state, as the main visual halves its rate); the view scales the picture up.
- Q: Do safety rules apply? → A: Yes: each preview's frame passes the same flash envelope pass as the main visual with the current safety clamp (Reduce flashing or the ACC-012 profile, FX-019); flagged presets cannot be compared while Reduce flashing is on (as PRE-010).
- Q: Is anything stored? → A: No. A comparison lives in memory only; no settings key, no file. Closing the browser cancels a waiting pick and ends a comparison.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How do VoiceOver users follow the comparison? → A: Each preview is one image element labelled "Preview A, <name>" (or B, or its loading or failure text); opening the sheet announces "Comparing <A> and <B>" on the library lane (`announceLibrary`), and Play A/B carry hints ("Plays <name> and closes the browser").
- Q: Can A and B be changed or swapped inside the sheet? → A: No: the sheet compares the two picks; Close and pick again for others. This keeps one session per sheet and the lockstep simple.
- Q: What does a pane show before its first frame and when a preset never draws? → A: "Loading…" until the first frame; a pane with no frame after 20 s (simulator shader compiles take seconds) or whose preset fails to load says "<name> could not be shown." and the other keeps drawing.
- Q: Does Compare work when the main visual is not projectM (camera, photo, native)? → A: Yes: the comparison reads the same live input; the shown visual is paused while the sheet is open and the app's normal visual switch (`resumeActiveVisual`) restores whichever visual was shown when it closes.
- Q: Which frame rate is "30 fps" measured against, and does it change during a session? → A: The tick rate is fixed when the session starts (30, or 15 under Low Power Mode or a serious thermal state); frame times stay n / rate for the whole session so they never jump.

### Session 2026-11-18 (QA-011 device run)

- Q: PRE-009-T13 found no "Compare…" in the first Calm row's menu on D1-D3; is the action missing? → A: No: that row was the playing preset, whose menu offers no comparison (R1). The device test leaves out the row whose label says "current preset".

### Session 2026-11-24 (QA-011 D3 r27: main visual after Close)

- Q: PRE-009-T13's "main visual after Close" read 52 fps on D3 (floor 55) with the controls card up
  (`controlsShown=1`), although the test waits 8 s for the controls to hide. Is the main visual slow after a
  comparison? → A: The reading was taken with the controls up only because of the auto-hide defect (FR-042
  Clarification 2026-11-24): the browser was open for over 60 s, its auto-hide fired meanwhile and was never
  restarted, so the 8 s wait ran out with the card still up. With the fix the controls hide 5 s after Done, inside
  the existing wait; the test and its 55 fps floor are unchanged. Rerun PRE-009-T13 on D3.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compare two presets live (Priority: P1) — MVP

In the browser I touch and hold "Aurora", choose Compare…, then touch and hold "Nebula" and choose Compare with
Aurora. A sheet shows both moving to the music, A beside B. I tap Play B: Nebula plays and the browser closes.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: A UI test opens Compare from the browser with two presets and chooses B; the main screen then
shows B as the current preset.

**Acceptance Scenarios**:

1. **Given** the browser, **When** I choose Compare… on one row and Compare with … on another, **Then** the Compare sheet shows both presets with their names.
2. **Given** the Compare sheet, **When** I tap Play B, **Then** B plays, the sheet and the browser close and the list B was picked from is the scope.
3. **Given** a pick waiting for its partner, **When** I tap Cancel in the bar or close the browser, **Then** nothing is compared and nothing changed.

### User Story 2 - Both previews see identical audio and time (Priority: P1)

**Why this priority**: It is the row's acceptance ("Both previews respond to identical sample timestamps").

**Independent Test**: An off-screen test (real engines on the simulator GPU) records, for every frame and each
preview, the sample range, the block's content checksum and the frame time delivered, and asserts the two records
are identical over many frames, also when one preview is made slower.

**Acceptance Scenarios**:

1. **Given** a running comparison, **When** N ticks of audio are submitted, **Then** A and B have received the same sequence of (first sample, sample count, checksum, frame time) and every submitted sample reached both or neither.
2. **Given** preview B draws slowly, **When** ticks arrive faster than the worker draws, **Then** both previews skip display frames together and still receive identical records; no preview runs ahead.
3. **Given** the same preset as A and B, **When** they are compared, **Then** their frames are pixel-identical (same input, same time, same picture).

### User Story 3 - The comparison respects the app's limits (Priority: P2)

**Acceptance Scenarios**:

1. **Given** Reduce flashing is on, **When** a preset is flagged, **Then** it offers no Compare; both previews pass the flash envelope.
2. **Given** a comparison, **When** the app leaves the screen, **Then** the comparison stops drawing (PERF-011) and the sheet says so.
3. **Given** a preset that fails to load, **When** it is compared, **Then** its pane says it could not be shown and the other preview keeps going.

### Edge Cases

- Choosing the same preset as A and B: the second Compare is not offered on A itself.
- A locked or excluded preset: not offered (it is not previewable).
- The renderer has no second engine (GLES fallback): Compare is not offered.
- A quick Close then Compare again while the previous worker is still finishing: the new comparison starts once it has ended (the sheet shows loading).
- A preset that compiles slowly: "Loading…" until its first frame, at most 20 s, then "could not be shown".
- Memory pressure while comparing: the comparison is optional work and stops (PERF-006).

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-009-R1**: Every previewable browser row offers Compare… (menu and VoiceOver action); with a waiting pick A it offers "Compare with <A>" on every other previewable row.
- **PRE-009-R2**: A waiting pick shows a bottom bar with the A name and Cancel; Cancel and closing the browser clear it.
- **PRE-009-R3**: Choosing B opens the Compare sheet: two labelled live previews (side by side when wide, stacked when tall), Play A, Play B, Close.
- **PRE-009-R4**: Play A/B closes the sheet and chooses that preset exactly as tapping its row would (scope, purchase, ACC-002 warning, PRE-012 guard).
- **PRE-009-R5**: One shared timeline stamps each tick with its frame time (tick n at n / rate) and sample range; both engines receive the identical PCM block(s) and identical frame time before each draw. No preview reads audio by itself.
- **PRE-009-R6**: Lockstep: both previews are drawn for every batch; waiting ticks are merged into one batch for both; more than 6 waiting ticks drop the oldest for both. A slow preview never makes the two drift.
- **PRE-009-R7**: With no live audio, ticks carry a deterministic test signal (shared), and the sheet says so.
- **PRE-009-R8**: Previews draw at 320 × 180 at 30 fps, 15 fps under Low Power Mode or a serious thermal state.
- **PRE-009-R9**: Each preview passes the FX-019 flash envelope with the current safety clamp.
- **PRE-009-R10**: The main visual pauses while the Compare sheet is open and resumes when it closes.
- **PRE-009-R11**: A preview whose preset fails to load says so; the other keeps drawing.
- **PRE-009-R12**: The comparison stops while the app cannot present (PERF-011) and on memory pressure (PERF-006); nothing is kept after it ends.
- **PRE-009-R14**: Each preview is one accessibility element ("Preview A, <name>"); opening announces "Comparing <A> and <B>" on the library lane; a pane with no frame after 20 s says it could not be shown.
- **PRE-009-R13**: Nothing is stored: no UserDefaults key, no file; no networking.

### Key Entities

- **Comparison tick**: index, frame time, first sample index, sample count, interleaved stereo samples.
- **Comparison batch**: the ticks the worker takes at once: first and last tick, last frame time, joined samples, dropped tick count.
- **Delivery record**: what one preview received for one drawn frame (batch tick range, frame time, sample range, checksum).
- **Comparison pick**: a preset and the list it was picked from (A waiting; A and B in a session).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-009-S1**: Over at least 30 drawn frames, A's and B's delivery records are identical, with B slowed and without.
- **PRE-009-S2**: With B slowed, at least one batch merges several ticks and no tick reaches only one preview.
- **PRE-009-S3**: The same preset as A and B gives pixel-identical frames.
- **PRE-009-S4**: The UI path (Compare…, Compare with…, Play B) finishes in a UI test under 30 s and B is then current.
- **PRE-009-S5** {device}: On D1, a 60 s comparison keeps the app responsive, each preview at or near its frame rate, without a thermal state above fair (recorded, not gated on the simulator).

## Assumptions

- The live input reaches the comparison through the renderer's attached reader, read on the main thread (its only consumer), so the latency offset (AUD-013) applies as on the main visual.
- Simulator rendering is not performance evidence (Constitution X); S5 needs D1.
- The projectM engine is unchanged (Constitution VIII); the comparison uses existing bridge calls (`addPCMInterleavedStereo`, `setFrameTime`, `renderFrameToFramebuffer`).
