# Feature Specification: VIS-020 Spectrum Waterfall

**Feature Branch**: `feature/vis-020` (spec directory `267-vis-020-spectrum-waterfall`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-020 (Spectrum waterfall) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Scroll spectrogram history through a fixed-size ring texture." Acceptance, verbatim: "Sixty
seconds of input yields correct time order without texture growth." P1, L, depends on ANL-002 (log-frequency bands,
integrated). Keep the projectM backend isolated; follow the shader policy."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-020-R1…`, success criteria `VIS-020-S1…`, tasks `VIS-020-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-003-R13 (palette, colour-blind
safe option), ACC-012 (brightness below full white); VIS-001-R12 to R16 (native visual contract); VIS-003-R12 (scene
capture); VIS-013 (noise field generator, reviewed compile site ADR-0066); VIS-014, VIS-015 (modes of that generator);
ANL-002 (log-frequency bands), ANL-003 (attack/release smoothing); FX-019 (strobe safety envelope); PERF-009 (native
pipeline archive); QA-002 (golden images).

## Baseline: what exists today (audit of 2026-11-14, commit `94100948`)

This is a gap row. The audit confirms the gap: no file in `Packages/` or `Apps/` mentions a waterfall or spectrogram.

| Area | Today | Gap for this row |
|---|---|---|
| Spectrum visuals (VIS-001, VIS-002) | Draw the current ANL-002 bands, smoothed by ANL-003 in the native host, as bars. | Only the present moment; no history. |
| Noise field generator (VIS-013/014/015) | One reviewed Metal compile site (ADR-0066) with three fragment entry points and lazily built pipelines, an 8 × 8 CPU flash estimate over FX-019's 17 areas, palette, Reduce Motion, goldens, app wiring. | No texture input; nothing kept between frames on the GPU. |
| Native host | Feeds every spectrum visual the smoothed bands (16, 32, 64 or 128, per Bars) and an injected frame clock. | No visual keeps a time history of them. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: Where does the waterfall live? → A: A fourth mode of VIS-013's noise field generator (beside plain, kaleidoscope and tunnel), with its own fragment entry point and lazily built pipeline in the same reviewed compile site (ADR-0066), so no new compile site, no allow-list change and no ADR; its shader text is part of `NoiseFieldGenerator.shaderSource`, so PERF-009's archive key covers it. It reuses the palette, flash envelope, Reduce Motion, glow and host wiring. Rejected: a new generator (second compile site and duplicated host wiring) (VIS-020-R1, R2).
- Q: How is the history stored? → A: A ring of 512 rows × 256 columns of 8-bit levels, allocated once when the generator is made and never reallocated — not on a resize, a palette, Bars or mode change, nor a restart. A CPU ring (pure Swift, testable on Linux) is the source of truth; the GPU texture of the same size is updated each frame with only the rows written since the last frame, copied in the frame's own command buffer before the draw, so the draw never reads a half-written row. Rejected: a texture that grows or is recreated with the output size (the acceptance forbids growth); writing the texture from the CPU while earlier frames may still read it (VIS-020-R3).
- Q: How fast does it scroll? → A: One row per fixed time step on the injected frame clock: 60 s / 512 = 117.1875 ms, so 60 s of input fills the ring exactly, at any frame rate. A row holds the mean of the frames whose timestamps fall in its interval; when a frame skips intervals (a stall), the skipped rows repeat the newest frame's levels; at most 512 rows are written in one frame; time running backwards re-anchors the clock without writing. Rejected: one row per frame (the history's span would depend on the frame rate) (VIS-020-R4).
- Q: Which way does it run, and what is the frequency axis? → A: Newest row at the top, older rows move down; low frequencies left, high right. The columns are the input bands (ANL-002's log-frequency bands after ANL-003's smoothing, the same input the spectra draw), interpolated across band index to 256 columns, so the axis is log-frequency at any Bars setting. Rejected: newest at the bottom (reads as rising, against the convention of a falling waterfall) (VIS-020-R5).
- Q: Colour and brightness? → A: Level v (0…1) picks the colour from the shared 16-stop palette at position v (so the colour-blind-safe palette of ACC-003 applies) and scales it by v, so silence is black; the whole frame is multiplied by 0.8 (ACC-012: below full white) and by the FX-019 envelope's gain (VIS-020-R6).
- Q: How is flash safety estimated for a picture that is a texture? → A: The 8 × 8 estimate cells (two per safety tile each way) each take the exact mean linear colour of the history texels they show (32 columns × 64 rows each), recomputed only from the rows that changed; the envelope solves the gain over the 17 areas from these, every frame, with Reduce flashing as for every native visual. A waterfall changes by at most one row in 64 per cell per step, so it is slow by construction (VIS-020-R7).
- Q: What does Reduce Motion do? → A: It halves the scroll speed: the row step doubles to 234.375 ms (the ring then spans 120 s), from the next row; storage is unchanged. Rejected: pausing (the visual would stop showing the music) (VIS-020-R8).
- Q: Which settings? → A: No new setting key. Bars applies (it sets how many bands feed the columns); palette and glow are shared. Accessibility: identifier `spectrumWaterfall`, label "Spectrum Waterfall visualization", value "Newest at top, Glow off". A loop restart (the host's) clears the history. Rejected: a history-length setting (would need a different ring size or a non-exact fill) (VIS-020-R9, R12).
- Q: Is the waterfall saved in scenes? → A: No, as VIS-013 to VIS-015: it is no SCN-001 layer kind; a scene captured while it is shown records no native layer (VIS-020-R11).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the last minute of sound (Priority: P1)

A user chooses "Spectrum Waterfall" and sees the spectrum of the last minute as a falling picture: the newest sound at
the top, bass at the left, treble at the right, louder sound in brighter palette colours.

**Why this priority**: It is the roadmap row and its acceptance.

**Independent Test**: Feed the history a synthetic input whose spectrum encodes time (a band that steps once per
second) on an injected clock; read rows from oldest to newest.

**Acceptance Scenarios**:

1. **Given** 60 s of input at any frame rate, **When** the rows are read oldest to newest, **Then** they are in exact time order and the ring is exactly full.
2. **Given** more than 60 s of input, **When** the rows are read, **Then** the oldest rows have been overwritten and the order still holds.
3. **Given** a known history, **When** rendered on the GPU, **Then** the picture shows the rows newest at the top in order, and matches the committed golden image (macOS host and iOS Simulator).

---

### User Story 2 - Fixed memory (Priority: P1)

However long the app runs, and whatever size the screen or window becomes, the waterfall's memory stays the same.

**Acceptance Scenarios**:

1. **Given** 60 s of frames and output-size changes, **When** checked, **Then** the history storage and GPU texture are the same objects with the same byte count as at the start.

---

### User Story 3 - Safe and calm (Priority: P1)

**Acceptance Scenarios**:

1. **Given** bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
2. **Given** Reduce Motion, **When** drawn, **Then** it scrolls at half speed.
3. **Given** full-level input, **When** drawn, **Then** no pixel is brighter than 0.8 of full white.

---

### User Story 4 - Choose it (Priority: P1)

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Spectrum Waterfall, **Then** it replaces the visual without restarting the audio source, and Bars is offered.
2. **Given** the waterfall and another noise-field mode, **When** switching between them, **Then** the same generator changes mode from the next frame.

### Edge Cases

- Output size 0: nothing drawn. Any output size samples the same 512 × 256 history.
- No bands (count 0) or non-finite levels: the row's levels are 0.
- Fewer than 512 rows written: the unwritten rows are black.
- Long stalls (more than 60 s between frames): at most 512 rows are written; the ring holds the newest level.
- Time running backwards: no row is written; the clock re-anchors at the new time.
- Bars changed mid-history: earlier rows keep their resolution; new rows use the new band count.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-020-R1**: The waterfall MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-020-R2**: It MUST be a mode of VIS-013's reviewed noise field generator with its own entry point; the other modes' frames MUST be unchanged; no new shader compile site.
- **VIS-020-R3**: History: a ring of 512 rows × 256 columns of 8-bit levels and a GPU texture of the same size, both allocated once and never reallocated; only rows written since the last frame are copied to the texture, ordered before the draw in the same command buffer.
- **VIS-020-R4**: Scroll: one row per 117.1875 ms of the injected frame clock (60 s fills the ring); a row is the mean of the frames in its interval; skipped intervals repeat the newest frame's levels; at most 512 rows per frame; time backwards re-anchors without writing.
- **VIS-020-R5**: Picture: newest row at the top; columns are the input bands interpolated across band index (log-frequency) to 256 columns, low at the left.
- **VIS-020-R6**: Colour: palette at position v × v × 0.8 × envelope gain.
- **VIS-020-R7**: Flash safety: every frame passes FX-019's envelope over the 17 areas from 64 cell means of the shown history texels; no allocation per frame.
- **VIS-020-R8**: Reduce Motion (ACC-001): the row step doubles from the next row; storage unchanged.
- **VIS-020-R9**: The app MUST offer "Spectrum Waterfall" as a Visual choice (stored `spectrumWaterfall` under `settings.visual`); Bars, palette and glow apply; no new key.
- **VIS-020-R10**: A golden image of the waterfall MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-020-R11**: Scene capture records the waterfall as no native layer (as VIS-003-R12).
- **VIS-020-R12**: Accessibility (FR-070): one element labeled "Spectrum Waterfall visualization", identifier `spectrumWaterfall`, value "Newest at top, Glow off".
- **VIS-020-R13**: The other native visuals MUST NOT change behaviour: their tests pass; the package builds in the Linux shape.

### Key Entities

- **Waterfall history**: 512 rows × 256 columns of levels, a write position, a per-row sequence number, the row clock (anchor, step) and the current row's running sum.
- **Noise field configuration**: VIS-013's, plus `waterfall` (on/off; on forces the other modes off).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-020-S1**: After 60 s of a step-per-second input at 60 and 24 frames per second, the 512 rows read oldest to newest carry consecutive sequence numbers 0…511, and every row that lies inside one second shows that second's band; after 75 s the oldest row is number 128 and the order still holds.
- **VIS-020-S2**: Over 60 s of frames and three output sizes, the history's byte count stays 131,072 and its storage and texture identities never change.
- **VIS-020-S3**: A GPU render of a known history shows each displayed row band from the matching history row, newest at the top (each sampled pixel within 0.02 of the CPU mirror).
- **VIS-020-S4**: Bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off; no pixel above 0.8 of full white.
- **VIS-020-S5**: The waterfall's golden passes on the macOS host and the iOS Simulator; the other modes' goldens and digests are unchanged.
- **VIS-020-S6**: One UI test of at most 30 s chooses Spectrum Waterfall with the source started once.

## Assumptions

- Bands come from the native host's own analysis (ANL-002) smoothed by ANL-003, the same input the spectra draw.
- Simulator results are not device evidence; frame rate and look on D1 are `{device}` work.
- No new setting key; no new catalog parameter; no network; the privacy manifest does not change.
- projectM stays the default visual.
