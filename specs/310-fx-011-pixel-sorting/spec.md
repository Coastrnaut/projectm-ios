# Feature Specification: FX-011 Pixel Sorting Approximation

**Feature Branch**: `feature/fx-011` (spec directory `310-fx-011-pixel-sorting`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (FX-011-T01-T15 verified on the Mac and an own iOS 27.2 simulator; T16 `{device}` open)

**Input**: User description: "Implement FX-011 (Pixel sorting approximation) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Reorder luminance segments within a fixed GPU workload." Acceptance, verbatim:
"Threshold changes ordering; worst-case frame budget is enforced." P3, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-011-R1…`, success criteria `FX-011-S1…`, tasks
`FX-011-T01…`, research decisions `FX-011-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-006 to FX-010 (chromatic split, directional and radial blur, echo), FX-012 (mosaic), FX-014 (edge
outline; ADR-0114), FX-015 (vignette; ADR-0116), FX-016 (lens distortion; ADR-0117, the closest template), FX-019
(flash guard), FX-020 (effect chains; ADR-0054), ACC-005 (accessible sliders), PERF-004 (texture pool), PERF-009
(pipeline archive), SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy).

## Baseline: the audit (2026-11-15, commit `38cdcf5c`)

**No pixel sorting exists.** Searching the packages and the app for "pixel sort", "pixelSort" and "PixelSort" finds
nothing.

**Output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (linear premultiplied, half float) → FX-020's reorderable effects in `OutputEffectOrder` (Trails,
Color, Chromatic split, Directional blur, Radial blur, Echo, Mosaic, Edge outline, Lens distortion, Vignette) → FX-019
flash guard → output pass (grade, FX-002 tone map). Each effect is an own pass writing one pooled picture while active,
walked in `Compositor.encodeOutputEffects`, its shader a module constant spliced into the reviewed compile site in
`Compositor.init` and listed in `CompositorShaderSources.archived`; Color listed before it is folded into FX-020's grade
pass right before it; scenes store the entry only while it is on. Every existing effect is a fixed-cost per-pixel
fragment pass; none bounds its cost by a budget, because none has a cost that grows with a setting the way a sort does.
The composite flash guard already uses one compute dispatch with threadgroup memory (CMP-001).

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: What is a segment? → A: Along each row (or column, by the **direction** setting) the picture is cut into fixed
  **tiles** of `span` pixels starting at the left (top) edge. A pixel **qualifies** when its luminance (Rec. 709 weights
  on linear colour, 0.2126 R + 0.7152 G + 0.0722 B) is finite and at least the **threshold**. A segment is a maximal run
  of adjacent qualifying pixels inside one tile, so no segment is ever longer than `span`. Applied to FX-011-R3.
- Q: How are segments reordered? → A: Inside every segment the pixels are reordered by luminance, darkest first in the
  reading direction (left to right, top to bottom); pixels with equal luminance keep their original order (stable).
  Pixels that do not qualify keep their value and their place. A pixel is moved whole (colour and alpha together), so
  the output is a permutation of the input within each tile. Applied to FX-011-R4.
- Q: Which settings? → A: On/off (off by default), threshold 0…1 (default 0.5, step 0.01), span 4, 8, 16, 32 or 64
  pixels (default 32), direction horizontal or vertical (default horizontal). There is no strength: off is the only
  no-pass setting; the span cannot be set below 4. Applied to FX-011-R2.
- Q: What does "fixed GPU workload" mean? → A: The work per frame depends only on the frame size and the effective
  span, never on the picture: every pixel of every tile does the same fixed number of steps (one step per pixel of its
  tile) whether or not anything qualifies, and the effect is exactly one GPU dispatch per active frame. The workload is
  W × H × span "steps". Applied to FX-011-R5.
- Q: What does "worst-case frame budget is enforced" mean? → A: A hard budget **B = 132,710,400 steps per frame**
  (7680 × 4320 × 4 = 3840 × 2160 × 16 = 1920 × 1080 × 64). The **effective span** is the largest of 4, 8, 16, 32, 64
  that is not above the chosen span and keeps W × H × span ≤ B; if even span 4 exceeds B, the pass is **skipped** (the
  frame passes through and the skip is counted). So for every frame size and setting the encoded workload is at most B,
  and the pass is never encoded more than once per frame. Applied to FX-011-R6.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Is Pixel sort a global setting or a per-scene value? → A: Both, like FX-006 to FX-016: a global setting the
  visuals use, which a scene or effect-chain preset with an `fx.pixelSort` entry overwrites when opened; a scene without
  one leaves it alone. Applied to FX-011-R10, R11.
- Q: How are the values stored and read back? → A: Settings `settings.pixelSort.enabled` (a real Bool, absent → off),
  `settings.pixelSort.threshold` (a number; absent, unreadable or NaN → 0.5, out of range → nearest bound),
  `settings.pixelSort.span` (an integer; absent or unreadable → 32, otherwise the largest of 4, 8, 16, 32, 64 not above
  it, at least 4) and `settings.pixelSort.direction` (`horizontal` or `vertical`; anything else → horizontal), each
  written only when changed. In a scene entry: `threshold` (0…1), `span` (4…64, then the same rounding down to a choice)
  and `vertical` (0 or 1; ≥ 0.5 reads as vertical, like FX-014's `mode`). Applied to FX-011-R10, R11.
- Q: What do the controls show and say? → A: The Threshold readout is a whole percent ("50%"); VoiceOver says
  "Threshold" and ACC-005's percent value ("50 percent"), one percent per swipe. Span is a picker labelled "Span" with
  choices "4 px" … "64 px"; Direction is a picker with "Horizontal" and "Vertical". The footer says lower thresholds sort
  more of the picture, longer spans make longer streaks, very large displays may use a shorter span to stay within the
  frame budget, and the effect can shimmer on busy content. Applied to FX-011-R9.
- Q: Is the effective span or a budget skip shown to the user? → A: No: it is not an error and needs no action. The
  compositor exposes the last frame's effective span, its workload, dispatch count and the number of budget-skipped
  frames for tests and diagnostics; the footer explains the behaviour. Applied to FX-011-R6.
- Q: Which colour does the threshold judge? → A: The pass's own input as stored (linear, premultiplied half float: the
  composite or the previous effect's output, with Color folded in first when listed before it), so a transparent pixel
  has luminance 0 and qualifies only at threshold 0. No tone map or display encoding is applied before judging. Applied
  to FX-011-R3.

### Session 2026-11-15 (speckit-analyze)

- Finding A1 (coverage): R1's "every output" is met by the shared output chain (screen, external display, recording and
  capture all read `encodeOutputEffects`), as for FX-014 to FX-016; the GPU tests drive that chain. Finding A2
  (underspecification): the budget skip is tested on small frames by lowering the compositor's internal budget
  (`@testable import Compositor`), since a 16384-pixel frame is too large for a short test; the model tests cover the
  real B over all sizes. Finding A3 (coverage): T10 now runs `SettingsTests`, `LibraryBackupAppTests` and
  `LibraryEraseAppTests` before committing (agent rules). No constitution conflicts; 14/14 requirements and 8/8 success
  criteria have tasks (S8 is the `{device}` task T16).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sort bright streaks (Priority: P1)

A performer shows the Video visual and turns on Settings → Pixel sort: bright runs of each row melt into smooth
dark-to-bright streaks while dark areas stay as they were. Lowering the threshold lets more of the picture streak;
switching the direction makes the streaks vertical.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: a fixed test picture through two thresholds gives two different pictures, each with every segment
sorted and every non-qualifying pixel unchanged.

**Acceptance Scenarios**:

1. **Given** Pixel sort on at threshold 0.5, **When** a picture is shown, **Then** inside every segment the luminance
   does not decrease in the reading direction and every pixel darker than the threshold is unchanged.
2. **Given** the same picture, **When** the threshold changes from 0.5 to 0.2, **Then** the output changes (more pixels
   qualify and are reordered).
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Never too expensive (Priority: P1)

However large the output (up to an 8K external display) and whatever the settings, the effect costs at most the fixed
frame budget; on a frame too large even for the smallest span it is skipped rather than slowing the show.

**Acceptance Scenarios**:

1. **Given** any frame size up to 16384 × 16384 and any span, **When** the effect is active, **Then** the work encoded
   for the frame is at most B and exactly one sort dispatch is encoded.
2. **Given** an 8K frame and span 64, **When** a frame is shown, **Then** the effect runs at span 4 (the budget's limit).
3. **Given** a frame larger than B ÷ 4 pixels, **When** a frame is shown, **Then** no sort runs and the frame passes
   through unchanged.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Pixel sort on the Effect order screen, saves a scene and an effect-chain preset, and gets the
same sort back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Pixel sort on, **When** it is opened, **Then** its values and position are restored; a
   scene without the entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes exactly
   as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit; a span that is not one of
  the five choices reads as the largest choice not above it (at least 4).
- A frame smaller than 2 pixels along the sort direction: passes through.
- The last tile of a row may be shorter than `span`; it is sorted the same way within its pixels.
- Non-finite pixel values never qualify, so they stay where they are; the sort only moves finite pixels, so finite input
  gives finite output.
- Transparent areas: premultiplied colour and alpha move together.
- Sensory safety: the sort only rearranges pixels within a tile (no brightness added); FX-019's flash guard still judges
  the shown frame. A threshold near a flickering luminance can make segments change frame to frame; the guard covers
  brightness changes, and the help text says the effect can shimmer on busy content.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-011-R1**: Pixel sort (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-011-R2**: Settings: threshold 0…1 (default 0.5, step 0.01), span one of 4, 8, 16, 32, 64 pixels (default 32),
  direction horizontal or vertical (default horizontal).
- **FX-011-R3**: Tiles, qualification and segments as clarified: tiles of the effective span from the left (top) edge;
  a pixel qualifies when the Rec. 709 luminance of its stored (linear, premultiplied) colour is finite and ≥ threshold;
  a segment is a maximal run of qualifying pixels within one tile.
- **FX-011-R4**: Within each segment the pixels are reordered so luminance is non-decreasing in the reading direction,
  ties in original order; non-qualifying pixels keep value and place; every pixel moves whole.
- **FX-011-R5**: Fixed workload: the per-frame work is W × H × effective span steps regardless of the picture, encoded
  as exactly one GPU dispatch per active frame.
- **FX-011-R6**: Frame budget B = 132,710,400 steps: the effective span is the largest allowed span ≤ the chosen span
  with W × H × span ≤ B; if none, the pass is skipped and counted. The encoded work never exceeds B. The effective span, workload, dispatch
  count and skip count are exposed for tests and diagnostics, not shown to the user.
- **FX-011-R7**: The effect is active only when on, the frame is at least 2 pixels along the sort direction and at least
  1 pixel across, and the budget admits a span; otherwise no pass runs, no picture is held and the output is
  bit-identical to the output before this feature.
- **FX-011-R8**: Pixel sort is an FX-020 reorderable output effect (`fx.pixelSort`), placed after Lens distortion and
  before Vignette in the standard order (Vignette stays last). Its position is honoured; the flash guard and the tone map
  always run after it.
- **FX-011-R9**: Settings has a "Pixel sort" section: a toggle and, while on, a Threshold slider with ACC-005 spoken
  values (percent), a Span picker, a Direction picker and help text. The Effect order screen lists it with its own
  switch.
- **FX-011-R10**: The values (`settings.pixelSort.enabled`, `.threshold`, `.span`, `.direction`) are saved on the device,
  restored at launch, included in library backups, erased with the other settings, checked on read, and removed by the
  UI-test reset.
- **FX-011-R11**: Scenes and effect-chain presets store the effect as an `fx.pixelSort` entry in FX-020's `effects` list,
  written only while it is on; out-of-range values are clamped and reported; scenes without it encode byte-identically.
- **FX-011-R12**: An active sort uses one pooled picture at output size and one dispatch per frame, no per-frame
  allocation; the picture returns to the pool when it turns inactive, the size changes or the visual is released.
- **FX-011-R13**: A plain-software reference of qualification, segments, the sort and the budget exists, testable without
  a GPU (Linux), and the GPU output matches it exactly (the sort moves pixels; it computes no new values).
- **FX-011-R14**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Pixel sort setting**: on/off, threshold, span, direction.
- **Sort plan**: for a frame size and setting, the effective span, the workload and whether the pass runs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-011-S1**: For a fixed test picture, thresholds 0.5 and 0.2 give different GPU outputs; each equals the software
  reference exactly, every segment is non-decreasing in luminance and every non-qualifying pixel is unchanged (both
  directions).
- **FX-011-S2**: Over frame sizes from 1 × 1 to 16384 × 16384 (including every common display and 7680 × 4320) and every
  span, the planned workload is ≤ B, the effective span is the largest admissible one, and frames too large for span 4
  are skipped; on the GPU, frames encode exactly one sort dispatch while active and zero when off or skipped.
- **FX-011-S3**: Off: output bit-identical to no effect, with no pass and no picture held.
- **FX-011-S4**: For finite random input, every output value is finite and each tile's output is a permutation of its
  input.
- **FX-011-S5**: Off renders the golden scene exactly as no chain; a saved pixel-sort scene reloads and renders the same
  picture.
- **FX-011-S6**: A scene and a preset with Pixel sort round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-011-S7**: A user can find Pixel sort, turn it on and change the threshold (UI test under 30 s); the values survive a
  relaunch (setting test with a reloaded store).
- **FX-011-S8**: The device GPU frame time with Pixel sort on at the default and the largest span is checked in the last
  stage (`{device}`).

## Assumptions

- The compositor, FX-006 to FX-016, FX-019 and FX-020 are as integrated.
- Stored effect orders written before this feature read with Pixel sort appended at the end (FX-020's existing rule for
  missing kinds); only the standard order places it before Vignette.
- No audio-reactive modulation of the threshold; no descending order or brightness-below mode (possible later
  features).
