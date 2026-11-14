# Feature Specification: VIS-004 Lissajous Scope

**Feature Branch**: `feature/vis-004` (spec directory `154-vis-004-lissajous`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-004 (Lissajous scope) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Plot stereo X/Y phase patterns
with persistence option." Acceptance, verbatim: "In-phase and quadrature fixtures yield
distinguishable stable shapes." P1, M, depends on ANL-002 (integrated). Model it on the native
visuals VIS-001 to VIS-003 (ADR-0009), the FX-001 glow, the FX-019 flash envelope, FX-009's trails
decay and the ACC-012 caps."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-004-R1…`, success criteria `VIS-004-S1…`, tasks `VIS-004-T01…`. Requirements of
other features are cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility),
FR-072 (Reduce flashing); VIS-001-R1, R12 to R16 (native visual contract, lifecycle, fallback);
VIS-003-R2, R9 to R14 (the sample path, the flash area model, settings, scene capture, golden);
FX-001-R10 (glow and flash safety); FX-009 (trails half-life and its ACC-012 caps); FX-019-R4, R9,
R11 (strobe safety envelope); ACC-003-R13 (palette); ACC-012-R4, R5 (sensory safety clamp); AUD-009
(channel selection); QA-002 / QA-003 (golden images, image diff).

## Baseline: what exists today (audit of 2026-11-14, commit `1fe5f95c`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 circular, VIS-002 linear spectrum and VIS-003 oscilloscope in `Packages/VisualGenerators`: CPU geometry, flat triangles drawn by the shared `FlatShapePass`, one host (`NativeSpectrumHost`) with one frame loop, glow chain, capture and recording path. | No visual plots one channel against the other. |
| Samples for visuals | VIS-003's `WaveformTap` wraps the analysis tap (44.1 kHz, stereo) and keeps a **mono** history ((L + R)/2, 4,096 samples) in a wait-free triple buffer. | The stereo pair is thrown away: a stereo history is needed. |
| Persistence | FX-009 Trails is a whole-output feedback pass in the compositor with a half-life (0.05…0.5 s) capped by ACC-012 (≤ intensity limit × 0.5 s, ≤ 0.25 s with Reduce flashing, cap 0 = off). Native visuals have no per-visual persistence. | A per-visual phosphor-style fade, bounded the same way. |
| Gain | The oscilloscope draws samples at a fixed scale (full scale reaches 90 % of the half height). | Quiet stereo audio would be a dot: an automatic gain is needed. |
| Choosing a visual | Settings → Visual lists one row per `VisualChoice`; native visuals show their own options and Glow. | A new choice and its options. |
| Golden images | VIS-003 keeps generator-level goldens (QA-002 rule, QA-003 `ImageDiff`) in `RenderGoldens/GeneratorGoldens/<class>/`. | Goldens of the two Lissajous shapes. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated, no
human interaction); each answer is the conservative, local-first option, recommended option first.

- Q: How do stereo samples reach the visual? → A: VIS-003's pass-through `WaveformTap` also keeps a stereo history (the newest 2,048 frames, interleaved L, R; same 4,096-float slot) published through a second `WaveformFrameBuffer`, on the same analysis worker. The mono history, the bands and the ANL-016 pipeline are unchanged. Rejected: a second tap reader (single consumer by contract); a separate tap type (a second wrapper in the reader chain for the same frames) (VIS-004-R2).
- Q: Which axes? → A: Two plots, a user option: **X/Y** (default; x = left, y = right, so a mono signal is the 45° diagonal, as the roadmap row names "X/Y") and **Mid/Side** (the goniometer convention: the X/Y plot rotated 45°, x = (R − L)/√2, y = (L + R)/√2, so mono is vertical and a left-only signal leans up-left). Rejected: Mid/Side only (the row says X/Y); a free rotation angle (no use beyond the two conventions) (VIS-004-R3).
- Q: What is drawn? → A: The newest 1,024 stereo frames (≈ 23 ms) as a polyline of 1,023 flat segments (butt ends, no joins: consecutive segments of a Lissajous trace are short and nearly collinear), colored along the trace with the active palette (oldest to newest, ACC-003-R13), line thickness 0.6 % of the output's shorter side (at least 1 px), centred, the auto-gain level reaching 90 % of the half of the shorter side. No additive blending: segments draw with the shared premultiplied "over" pass, so overlaps never get brighter than one segment and the flash area model's count of overlaps can only overestimate. Rejected: additive points (brightness would grow with how often the trace crosses itself, which flash safety would have to bound separately; a new blend pipeline) (VIS-004-R4, R5).
- Q: How is quiet audio made visible? → A: An automatic gain with hold: the level follows the window's peak |coordinate| at once on a rise, holds for 0.5 s after the last rise, then falls with a 0.5 s half-life but never below the current peak or 0.01 (at most 40 dB of gain). Time is the frame context's frame duration (clamped to 0…0.1 s), never the wall clock, so it is deterministic under an injected clock. Silence (peak below 0.0001, −80 dBFS) draws nothing (VIS-004-R6, R7).
- Q: How does persistence work and how is it bounded? → A: Optional, off by default (key `settings.lissajous.persistence`). On, the visual keeps up to 8 snapshots of its trace (128 points each, taken every half half-life of frame time, not during silence) and draws them behind the live trace, oldest first, each with its colors scaled by 0.5^(age / half-life) and dropped at 4 half-lives (weight 1/16). The half-life is 0.2 s (FX-009's default) and is capped exactly like FX-009 Trails under ACC-012: at most intensity limit × 0.5 s when the profile caps intensity, at most 0.25 s with Reduce flashing, and a cap of 0 turns persistence off. Snapshots count in the flash area model with their weighted colors. Rejected: a GPU accumulation texture (state only testable on a GPU, a second pass and texture per size); reusing the compositor's Trails pass (the native host has no compositor) (VIS-004-R8, R9).
- Q: What about a mono source? → A: A mono source (identical channels) draws the diagonal in X/Y and the vertical line in Mid/Side; AUD-009's channel selection other than Mix writes the selected signal into both channels, so the Lissajous then also shows a line. This is documented in the Settings footer (VIS-004-R10).
- Q: Settings and scenes? → A: A new Visual choice "Lissajous" (stored value `lissajous`) with Plot (X/Y, Mid/Side; key `settings.lissajous.mode`, values `xy`/`midSide`, anything else → xy) and Persistence (Bool, absent → off). Glow is shared; Bars is hidden. Scene capture records it like the oscilloscope: no native layer (VIS-003-R12). Both keys join the three key lists (FR-065 settings, FILE-005 backup policy, the device privacy allow list) (VIS-004-R11, R12).

- Q (clarify pass): Should the user choose the time span of the trace? → A: No: a fixed 1,024 frames (≈ 23 ms). Two settings keys only (plot, persistence) as the brief asks; the span already shows several cycles above about 90 Hz, and persistence lengthens the visible history. Rejected: VIS-003's 10/20/40 ms choice (a third key with little visible effect on a phase plot) (VIS-004-R4).
- Q (clarify pass): What does changing the plot mode or persistence do while running? → A: It applies from the next frame without rebuilding the generator; a mode change clears the snapshots (ghosts in the old orientation would be misleading) and keeps the gain level; turning persistence off clears them. Pause/resume (the host's loop restart) resets both gain and snapshots (VIS-004-R8, Edge Cases).
- Q (clarify pass): Does the stereo history cost anything when another visual is shown? → A: The tap keeps it whenever the native host runs (one extra copy of at most 16 KB and one atomic exchange per analysis read, on the analysis worker), the same rule as VIS-003's mono history; nothing runs on the audio callback and nothing allocates. Rejected: a switch to enable it only for the Lissajous (a cross-thread flag for a negligible saving) (VIS-004-R2, R17).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the stereo image of the music (Priority: P1)

A user playing music opens Settings, chooses the visual "Lissajous" and sees the left channel plotted
against the right: a mono passage is a thin diagonal line, wide stereo fills a cloud, out-of-phase
content leans the other way. The user can switch the plot to Mid/Side (the goniometer view, mono
vertical) and turn on Persistence, which leaves a fading afterglow of recent traces. Quiet music is
still visible. Choices are remembered.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose Lissajous in Settings, check the Plot option (X/Y by
default) and that Bars is hidden, choose Mid/Side, close Settings and check that the Lissajous visual
is shown and its value names Mid/Side.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Lissajous", **Then** it replaces the current visual without restarting the audio source.
2. **Given** Lissajous chosen, **When** Settings is open, **Then** Plot (X/Y, Mid/Side), Persistence and the Glow controls are offered and Bars is not.
3. **Given** Mid/Side and Persistence chosen, **When** the app is relaunched, **Then** both are restored.

---

### User Story 2 - In-phase and quadrature give distinguishable stable shapes (Priority: P1)

Whoever checks the visual feeds an in-phase fixture (L = R sine) and a quadrature fixture (R = L
shifted 90°) and sees a line and a circle, the same every frame.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Lay out both fixtures on the CPU and measure the ratio of the trace's minor to
major principal axis; render both on the GPU and compare them with golden images.

**Acceptance Scenarios**:

1. **Given** the in-phase fixture, **When** laid out in X/Y, **Then** every point lies on the diagonal and the minor/major axis ratio is below 0.02.
2. **Given** the quadrature fixture, **When** laid out, **Then** the points lie on a circle (radius spread below 2 % of the mean radius), both axes are equal within 2 % and the ratio is above 0.95.
3. **Given** either fixture held steady, **When** laid out on successive frames, **Then** the metric is identical frame to frame; a phase-advancing fixture keeps it within 0.01.
4. **Given** Mid/Side, **When** the in-phase fixture is laid out, **Then** the line is vertical.
5. **Given** both fixtures rendered offscreen, **When** compared with the committed goldens, **Then** they pass QA-002's rule.

---

### User Story 3 - Safe and calm: gain, silence, persistence limits, flash safety (Priority: P2)

Quiet audio is scaled up but deterministically; silence draws nothing; persistence fades at its
half-life and obeys the sensory safety caps; the strobe envelope bounds every frame.

**Independent Test**: Feed quiet, loud and silent fixtures with an injected frame duration; read the
level, the snapshot weights and the envelope's transition counts.

**Acceptance Scenarios**:

1. **Given** a sine at amplitude 0.05, **When** laid out, **Then** the trace reaches 90 % of the half size.
2. **Given** a loud passage followed by a quiet one, **When** frames advance, **Then** the level holds for 0.5 s, then halves every 0.5 s until it meets the quiet peak.
3. **Given** silence, **When** laid out, **Then** nothing is drawn (zero vertices) without persistence.
4. **Given** persistence on, **When** frames advance, **Then** each snapshot's weight is 0.5^(age / half-life) and snapshots older than 4 half-lives are gone.
5. **Given** a profile that caps intensity at 0.2 or Reduce flashing, **When** the half-life is resolved, **Then** it is 0.1 s or at most 0.25 s; a cap of 0 turns persistence off.
6. **Given** a loud/silent alternation at 60 Hz, **When** drawn with Reduce flashing on, **Then** no area has more than 4 transitions per second (6 with it off).

### Edge Cases

- Mono input: the diagonal (X/Y) or the vertical line (Mid/Side).
- Fewer frames than the window (just after start): older frames read 0 (silence) and draw at the centre only if the newest are not silent.
- NaN or infinite samples: treated as 0.
- One channel silent: a line along that channel's axis.
- Output size 0: nothing drawn; tiny sizes give valid geometry.
- Pause and resume: the gain and the snapshots start afresh (no ghost of the picture before the pause).
- Persistence turned off while ghosts are visible: they disappear at the next frame.
- Plot mode changed while running: the snapshots are cleared, the gain level kept; effective from the next frame.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-004-R1**: The Lissajous scope MUST be a native visual under VIS-001's generator contract and the shared host contract (`SpectrumTextureGenerator`), drawn by the shared flat-triangle pass; its input vector is the interleaved stereo history (L, R; oldest first).
- **VIS-004-R2**: Stereo samples MUST reach the frame loop through VIS-003's pass-through tap without changing the reads it forwards, the mono history or the bands: a stereo history of the newest 2,048 frames published wait-free; no allocation per read.
- **VIS-004-R3**: Plot modes: X/Y (x = L, y = R; default) and Mid/Side (x = (R − L)/√2, y = (L + R)/√2).
- **VIS-004-R4**: Geometry: the newest 1,024 frames, mapped by the mode, divided by the gain level, clamped to ±1, placed at (W/2 + u·r, H/2 − v·r) with r = 0.9 × min(W, H)/2; 1,023 rectangular segments of thickness max(0.006 × min(W, H), 1 px); zero-length segments are not drawn.
- **VIS-004-R5**: Colors: segment k's color is palette color k of the segment count (oldest first); premultiplied, linear; background opaque black.
- **VIS-004-R6**: Automatic gain: level = max(peak, held/decayed level, 0.01); a rise is followed at once; after 0.5 s without a rise it decays by 0.5^(Δt / 0.5 s), never below the current peak; Δt is the frame duration clamped to 0…0.1 s. Deterministic for a given sequence of inputs and durations.
- **VIS-004-R7**: Silence (window peak < 0.0001) or non-finite-only input draws no trace.
- **VIS-004-R8**: Persistence (optional, off by default): up to 8 snapshots of 128 points, taken every half-life/2 of frame time while the trace is drawn; drawn behind the trace oldest first, snapshot segment k in palette color k of the snapshot's segment count, colors × 0.5^(age / half-life) (premultiplied); removed when age ≥ 4 half-lives; cleared when persistence turns off, the plot mode changes or the loop restarts.
- **VIS-004-R9**: Persistence half-life 0.2 s, limited under ACC-012 like FX-009 Trails: ≤ intensity limit × 0.5 s when the profile caps intensity, ≤ 0.25 s with Reduce flashing effective, off when the cap is 0. The host applies the clamp whenever the profile, Reduce flashing or the style changes.
- **VIS-004-R10**: A mono source draws a line (diagonal in X/Y, vertical in Mid/Side); the Settings footer says so.
- **VIS-004-R11**: The app MUST offer "Lissajous" as a Visual choice (stored `lissajous` under `settings.visual`) with Plot (`settings.lissajous.mode`: `xy`/`midSide`, anything else → xy) and Persistence (`settings.lissajous.persistence`, Bool, absent → off); Glow shared, Bars hidden. Switching does not restart the audio source; lifecycle and fallback are VIS-001-R12 to R16's. Both keys are FR-065 user settings, in the FILE-005 backup policy and the device privacy allow list, and are reset by `-uitestResetNotice`.
- **VIS-004-R12**: Scene capture records the Lissajous as no native layer (as VIS-003-R12).
- **VIS-004-R13**: Flash safety: every frame passes FX-019's envelope with the 17-area model built from the trace's and the snapshots' segments (FX-019-R4, R9, FX-001-R10), as the other native visuals.
- **VIS-004-R14**: Accessibility (FR-070): one element labeled "Lissajous visualization", identifier `lissajous`, value naming the plot, the persistence and the glow (for example "X/Y, Persistence off, Glow off"); each new control has a stable identifier.
- **VIS-004-R15**: Golden images of the in-phase and quadrature fixtures (X/Y, persistence off, glow off) MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator), with the record policy and integrity check.
- **VIS-004-R16**: The other native visuals MUST NOT change: their tests pass unchanged; the mono history stays bit-identical.
- **VIS-004-R17**: Real-time safety (Constitution VII): layout, tessellation, area levels and the tap's stereo copy allocate nothing per frame or read.

### Key Entities

- **Lissajous configuration**: plot mode, persistence half-life (0 = off), line thickness, palette, background.
- **Stereo history**: the newest 2,048 interleaved frames and a running frame count.
- **Gain state**: level and the time since the last rise.
- **Snapshot**: 128 normalized points and the frame time it was taken.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-004-S1**: In-phase fixture: minor/major axis ratio < 0.02; quadrature fixture: ratio > 0.95, radius spread < 2 %; the two differ by more than 0.9.
- **VIS-004-S2**: A steady fixture gives the same metric on 10 successive frames (bit-identical points); a phase-advancing one stays within 0.01.
- **VIS-004-S3**: Gain: a 0.05-amplitude sine reaches 90 % ± 1 % of the half size; the hold and release follow R6 within 1e-9 under the injected clock; silence yields 0 vertices.
- **VIS-004-S4**: Persistence: snapshot weights equal 0.5^(age / half-life) within 1e-9; none survives 4 half-lives; the ACC-012 caps give 0.1 s at intensity limit 0.2, ≤ 0.25 s with Reduce flashing and off at 0.
- **VIS-004-S5**: Both fixtures pass their goldens on the macOS host and the iOS Simulator.
- **VIS-004-S6**: One UI test of at most 30 s chooses Lissajous and Mid/Side with the source started once; the setting keys persist (unit test).
- **VIS-004-S7**: Every existing VisualGenerators and RenderGoldens test passes; the package builds in the Linux shape (`-DVISUAL_NO_METAL`).

## Assumptions

- The audio is the normalized ring's 44.1 kHz stereo analysis tap, after AUD-009 channel selection and AUD-008 trim.
- Simulator results are not device evidence; frame time on devices is `{device}` work.
- No new stored data besides the two setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual.
