# Feature Specification: VIS-019 Cymatic Line Patterns

**Feature Branch**: `feature/vis-019` (spec directory `308-vis-019-cymatic-line-patterns`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement VIS-019 (Cymatic line patterns) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Drive standing-wave geometry with selected spectral bands." Acceptance, verbatim:
"Pure tone changes nodal pattern while silence settles to baseline." Depends on ANL-002 (normalized log-frequency
bands, integrated). Test: Metal, CoreGraphics; keep the projectM backend isolated; golden image + simulator + device GPU."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-019-R1…`, success criteria `VIS-019-S1…`, tasks `VIS-019-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-003-R13 (palette), ACC-012
(brightness below full white); VIS-001-R12 to R16 (native visual contract); VIS-003-R12 (scene capture); VIS-007 (band
groups: thirds of the bands); VIS-013 and its modes VIS-011/012/014/015/017/020 (the noise field generator); ANL-002
(normalized bands); FX-019 (strobe safety envelope); PERF-009 (native pipeline archive); SHD-011 (shader policy);
QA-002 (golden images); FILE-005 (settings backup policy).

## Baseline: what exists today (audit of 2026-11-15, commit `0b6c3696`)

This is a gap row. The audit confirms the gap: no source, spec or document mentions cymatics, Chladni figures,
standing waves or nodal lines.

| Area | Today | Gap for this row |
|---|---|---|
| Full-screen procedural visuals (noise field, kaleidoscope, tunnel, waterfall, fluid ink, reaction diffusion, SDF shapes) | One generator with one module-constant shader, one entry point per mode, a CPU mirror sampled at 64 points for the FX-019 envelope, band-driven drives on the injected frame clock, palette, Reduce Motion, goldens. | No standing-wave geometry; no visual picks its shape from which band is loudest. |
| Band input (ANL-002) | 16/32/64/128 normalized log-frequency bands per frame; VIS-007 groups them into low, mid and high thirds. | No user selection of which bands drive a visual. |
| Spectrum visuals (VIS-001, VIS-002, VIS-020) | Show every band's level. | Level only; no geometry change per frequency. |
| Shader compile sites (SHD-011, `check_compliance.py`) | Reviewed files; the noise field generator is one (ADR-0066). | — (this row should add none). |

## Clarifications

### Session 2026-11-15

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: Where does the standing-wave field live? → A: As one more mode of the noise field generator (`NoiseFieldConfiguration.cymatic`, a settings value; nil = off, on forces every other mode off, the SDF shapes included), drawn by its own entry point in that generator's module-constant shader, exactly as VIS-017. No new shader compile site, no compliance or ADR change; the new text joins the PERF-009 archive key automatically. Rejected: a separate generator with its own `makeLibrary(source:)` (a reviewed compile-site change under SHD-011 / ADR-0024) (VIS-019-R1).
- Q: What field, which modes, and what exactly is a "nodal pattern"? → A: The square-plate (Chladni) field F(x, y) = cos(nπx)·cos(mπy) + s·cos(mπx)·cos(nπy) on the plate square x, y ∈ [0, 1] (the centred square on the shorter side, y up; it continues beyond the square), |F| ≤ 2. Eight driven modes (n, m, s) in rising complexity: (1,2,−), (1,3,+), (2,3,−), (1,4,−), (2,4,+), (3,4,−), (2,5,+), (3,5,−); the resting mode is (1,1,+) (a centred cross). The frame shows the weighted blend F̄ = Σ wₖFₖ / Σ wₖ. A pixel's line intensity is L = 1 − smoothstep(0, width, |F̄|), width = 0.08 + depth × amplitude (depth 0.06; 0.03 with Reduce Motion). The **nodal mask** of a frame is the set of pixels with L ≥ 0.5, i.e. |F̄| ≤ width / 2; for comparing patterns it is taken at amplitude 0 (|F̄| ≤ 0.04) so loudness does not count as a pattern change. "Pure tone changes nodal pattern" means: two pure tones whose loudest selected bands fall in different parts settle to different modes, and their nodal masks differ in ≥ 50% of their combined line pixels (|A △ B| / |A ∪ B| ≥ 0.5; the lines cover only about 2–7% of a frame, so a share of all pixels would mostly measure the dark background); the same tone from scratch gives the same frames bit for bit (VIS-019-R2, R3, R6; S1).
- Q: How do the selected bands choose the mode and amplitude? → A: Bands setting All (default), Low, Mid or High: All = every band; Low, Mid, High = VIS-007's thirds of the band array (bands [0, N/3), [N/3, 2N/3), [2N/3, N) — about 20–200 Hz, 200 Hz–2 kHz and 2–20 kHz on ANL-002's log scale). Each band value is sanitized (not finite or negative → 0, above 1 → 1). The loudest selected band (lowest index on ties) at index i, relative index r = i − start of R selected bands, falls in part ⌊8r / R⌋, which names the driven mode. Hysteresis: the target moves to a new part only when its loudest band is ≥ 1.25 × the loudest band of the current target's part (or the current target is rest). Amplitude target = the loudest selected band's level (VIS-019-R3, R5).
- Q: What are "silence", "baseline" and the settle time? → A: Silence = the loudest selected band below the floor 0.02. Then the target is the resting mode and the amplitude target 0. Every weight moves linearly toward its target (1 for the target mode, 0 for the others) at 2 per second (1 with Reduce Motion), so any blend reaches the target exactly within 0.5 s (1 s); amplitude rises at 4 and falls at 2 per second (halved with Reduce Motion), reaching 0 exactly within 0.5 s (1 s). Steps use the injected frame clock, at most 0.25 s per frame, never backwards; the first frame after a reset only anchors the clock. The **settle time** is 1 s (2 s with Reduce Motion): after that much silence the state equals the resting state (resting weight 1, others 0, amplitude 0) exactly, so the frame equals a never-excited generator's frame bit for bit when the FX-019 gain is 1 (VIS-019-R4, R5, R9; S2).
- Q: How is it coloured, kept safe, and named in the app? → A: Colour = the palette at t = Σ wₖtₖ / Σ wₖ (resting mode t = 0.5, driven mode k t = k / 7); value = (L + 0.15 × amplitude × (1 − L) × |F̄| / 2) × brightness, brightness = 0.35 + 0.45 × amplitude (≤ 0.8, ACC-012) × the FX-019 gain; NaN-guarded and clamped to 0…1. The FX-019 estimate is the CPU mirror at the 64 sample points. App: Visual choice "Cymatic Lines" (stored `cymatic`), key `settings.cymatic.bands` (`all`/`low`/`mid`/`high`; anything else → `all`), Bands as a segmented picker (`cymaticBandsPicker`); accessibility label "Cymatic Lines visualization", identifier `cymatic`, value "<Range> bands, <glow>" (e.g. "All bands, Glow off"). A range change applies in place from the next frame (same generator, the blend continues). No SCN-001 layer kind (VIS-019-R8, R10, R12, R13).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A tone draws its own figure (Priority: P1)

A user chooses "Cymatic Lines" and sees thin bright lines on a dark background, like sand gathering on the still lines
of a vibrating plate. When a steady tone plays, the figure takes a shape that belongs to that tone's frequency; a tone
in a clearly different part of the spectrum gives a clearly different figure; louder sound brightens the lines.

**Why this priority**: It is the roadmap row's observable behaviour and the first half of its acceptance.

**Independent Test**: Feed synthetic band frames (and band frames computed from synthetic pure tones) and render;
compare the nodal-line pixels of the resulting frames.

**Acceptance Scenarios**:

1. **Given** a steady pure tone whose loudest band lies in one part of the selected range, **When** the figure has settled, **Then** it shows the standing-wave figure assigned to that part.
2. **Given** a second pure tone in a different part of the selected range, **When** settled, **Then** the figure differs from the first tone's in a clearly measurable share of the picture.
3. **Given** the same tone twice from scratch, **When** rendered at the same times, **Then** the frames are identical.

---

### User Story 2 - Silence returns to rest (Priority: P1)

When the sound stops, the figure glides back to one fixed resting figure within a short, defined time, and then stays
exactly there.

**Why this priority**: The second half of the acceptance.

**Independent Test**: Drive a tone, then silence; after the defined settle time, the frame equals the resting frame of a
generator that only ever saw silence.

**Acceptance Scenarios**:

1. **Given** any figure and loudness, **When** silence (every selected band below the floor) lasts the settle time, **Then** the frame is exactly the resting frame.
2. **Given** Reduce Motion on, **When** silence lasts twice the settle time, **Then** the same holds.

---

### User Story 3 - Choose which sounds drive it (Priority: P2)

The user picks which bands drive the figure: All, Low, Mid or High. Only sound inside that range changes the figure;
sound outside it is treated as silence.

**Acceptance Scenarios**:

1. **Given** Bands set to Low and a high tone only, **When** drawn, **Then** the figure settles to rest.
2. **Given** a range change while running, **When** the next frame is drawn, **Then** the new range applies without restarting the source.
3. **Given** a range chosen, **When** the app is relaunched, **Then** it is restored; a stored value that is not a range falls back to All.

---

### User Story 4 - Smooth, safe and calm (Priority: P2)

Figures blend into each other rather than jumping; the lines never flash; brightness stays below full white; Reduce
Motion makes the blends half as fast and the loudness-driven widening half as deep. Invalid input never breaks the
picture.

**Acceptance Scenarios**:

1. **Given** a tone change, **When** frames are drawn, **Then** the figure crossfades over a bounded time.
2. **Given** bursts of sound alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
3. **Given** NaN, infinite, negative or above-range band values, huge times or time jumps, **When** drawn, **Then** every output value is finite and within 0…1.

### Edge Cases

- Output size 0: nothing drawn. Non-square outputs: the plate is the centred square on the shorter side; the figure continues beyond it.
- Ties between equally loud bands: the lowest band wins (deterministic).
- Two parts nearly equally loud: the current figure is kept unless the other is clearly louder (no flicker).
- Bands absent, NaN or negative: read as silence; above 1: read as 1. Every band count (16, 32, 64, 128) works.
- Time going backwards or long gaps: state never moves backwards and moves at most a bounded step per frame.
- Switching to and from the other noise-field modes keeps the generator; entering this mode starts from rest.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-019-R1**: Cymatic Lines MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-019-R2**: The picture MUST be the nodal lines (where the displacement is zero) of a standing-wave field built from a fixed table of plate modes, plus one fixed resting mode.
- **VIS-019-R3**: The loudest band within the user-selected range MUST choose the mode, the selected range being divided into equal parts, one mode per part; the loudest band's level sets the amplitude (line brightness and width).
- **VIS-019-R4**: When every selected band is below a silence floor, the state MUST move to the resting mode at zero amplitude and reach it exactly within a defined settle time, after which frames are identical to a never-excited generator's.
- **VIS-019-R5**: Mode changes MUST blend over a bounded time on the injected frame clock; a hysteresis rule MUST prevent flicker between nearly equal parts.
- **VIS-019-R6**: The same inputs at the same times MUST give identical frames.
- **VIS-019-R7**: Every output value MUST be finite and within 0…1 for any band input, time or output size; brightness stays below full white (ACC-012).
- **VIS-019-R8**: Flash safety: every frame passes FX-019's envelope over all 17 areas, estimated from a CPU mirror of the same field.
- **VIS-019-R9**: Reduce Motion (ACC-001) MUST halve the blend speed and the amplitude-driven widening.
- **VIS-019-R10**: The app MUST offer "Cymatic Lines" as a Visual choice (stored `cymatic` under `settings.visual`) with a Bands setting stored under one key; glow and palette shared; Bars hidden. The key is an FR-065 user setting, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-019-R11**: A golden image MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-019-R12**: Scene capture records the visual as no native layer (as VIS-003-R12).
- **VIS-019-R13**: Accessibility (FR-070): one element labeled "Cymatic Lines visualization" with a value naming the band range and glow; the Bands control has its own identifier.
- **VIS-019-R14**: The other native visuals MUST NOT change behaviour: their tests and goldens pass; the package builds in the Linux shape.

### Key Entities

- **Band range**: All, Low, Mid or High — which share of the bands drives the figure.
- **Plate mode**: two wave numbers and a sign that define one standing-wave figure.
- **Cymatic state**: the blend weight of every mode, the target mode, the amplitude, the last frame time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-019-S1**: Two pure tones whose loudest bands fall in different parts of the selected range settle to different modes, and their nodal-line masks differ in at least 50% of their combined line pixels (CPU mirror and GPU render).
- **VIS-019-S2**: After silence for the settle time (twice it with Reduce Motion), the state equals the resting state exactly and the GPU frame equals the resting frame bit for bit.
- **VIS-019-S3**: Two GPU renders from scratch are identical, and the golden passes on the macOS host and the iOS Simulator.
- **VIS-019-S4**: With extreme inputs, every pixel of a floating-point render is finite and within 0…1.
- **VIS-019-S5**: Bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-019-S6**: One UI test of at most 30 s chooses the visual and a band range with the source started once; the setting persists (unit test); the key is in every list.
- **VIS-019-S7**: New package tests take a few seconds in total; every existing test passes; the package builds in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis (ANL-002), as for every native visual; pure tones in tests come from the AUD-016 tone generator through the real band reducer, or from synthetic band frames.
- Simulator results are not device evidence; the look and frame rate on a device GPU are `{device}` work.
- One new setting key; no network; the privacy manifest does not change.
- projectM stays the default visual.
