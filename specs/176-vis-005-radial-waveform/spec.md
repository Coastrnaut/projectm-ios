# Feature Specification: VIS-005 Radial Waveform

**Feature Branch**: `feature/vis-005` (spec directory `176-vis-005-radial-waveform`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-005 (Radial waveform) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Wrap time-domain waveform around an adjustable ring." Acceptance,
verbatim: "Ring closes without seam and reacts to signed input samples." P1, M, depends on ANL-002
(integrated). Mirror the native visuals VIS-003 (oscilloscope) and VIS-004 (Lissajous)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-005-R1…`, success criteria `VIS-005-S1…`, tasks `VIS-005-T01…`. Requirements of
other features are cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility);
VIS-001-R1, R12 to R16 (native visual contract, lifecycle, fallback); VIS-003-R2, R9, R12 (the mono
sample path, the flash area model, scene capture); VIS-004-R6 (automatic gain), R15 (generator goldens);
FX-001-R10 (glow and flash safety); FX-019-R4, R9, R11 (strobe safety envelope); ACC-003-R13 (palette);
ACC-012 (sensory safety clamp); QA-002 / QA-003 (golden images, image diff).

## Baseline: what exists today (audit of 2026-11-14, commit `5aaeebe5`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 circular and VIS-002 linear spectrum, VIS-003 oscilloscope and VIS-004 Lissajous in `Packages/VisualGenerators`: CPU geometry implementing the flash region model, flat triangles drawn by the shared flat-shape pass, one host with one frame loop, glow, capture and recording. | No visual draws the waveform around a ring. |
| Samples for visuals | VIS-003's waveform tap keeps a mono history ((L + R)/2, 4,096 samples) published wait-free; VIS-004 added a stereo history. | Nothing: the mono history is enough. |
| Gain | VIS-004's automatic gain with hold (deterministic, frame-duration driven). | Reused as is. |
| Choosing a visual | Settings → Visual lists one row per visual choice; native visuals show their options and Glow; Bars only where `usesBars`. | A new choice and its options. |
| Golden images | VIS-003 and VIS-004 keep generator-level goldens per platform class. | Goldens of a sine ring and of silence. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the
conservative, local-first option.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the waveform wrapped around a ring (Priority: P1)

A user playing music opens Settings, chooses the visual "Radial Waveform" and sees the sound's
waveform drawn around a circle: loud passages push the ring outward and pull it inward, silence is a
calm perfect circle. The user can make the ring smaller or larger and the wobble gentler or stronger.
Choices are remembered.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose Radial Waveform in Settings, check that Ring and
Amplitude are offered and Bars is not, choose a ring size, close Settings and check that the visual is
shown and its value names the choice.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Radial Waveform", **Then** it replaces the current visual without restarting the audio source.
2. **Given** Radial Waveform chosen, **When** Settings is open, **Then** Ring (Small, Medium, Large), Amplitude (Low, Medium, High) and the Glow controls are offered and Bars is not.
3. **Given** a ring size and amplitude chosen, **When** the app is relaunched, **Then** both are restored.

---

### User Story 2 - The ring closes without a seam and follows the sign of the samples (Priority: P1)

Whoever checks the visual feeds a sine whose period does not fit the window a whole number of times
and sees a closed ring with no jump where the newest sample meets the oldest; feeds a positive constant
and sees the ring pushed outward everywhere, a negative constant and sees it pulled inward everywhere,
and silence, which is a perfect circle at the base radius.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Lay out the fixtures on the CPU and measure point distances and radii; render a
sine ring and silence on the GPU and compare them with golden images.

**Acceptance Scenarios**:

1. **Given** a sine whose period does not divide the window, **When** laid out, **Then** the largest distance between neighbouring points, the closing segment included, is at most 1.5 × the median neighbour distance.
2. **Given** the same sine without the seam treatment, **When** measured the same way, **Then** the ratio is far above 1.5 (the treatment is what closes the ring).
3. **Given** a constant +0.5 input, **When** laid out, **Then** every point's radius is greater than the base radius; **given** −0.5, every radius is smaller; **given** silence, every radius equals the base radius.
4. **Given** a fixture held steady, **When** laid out on successive frames, **Then** the points are identical frame to frame.
5. **Given** a sine ring and silence rendered offscreen, **When** compared with the committed goldens, **Then** they pass QA-002's rule.

---

### User Story 3 - Safe: flash safety and bounded geometry (Priority: P2)

Alternating loud and silent frames never flashes beyond the strobe envelope; the ring stays inside
the picture at any size and orientation.

**Independent Test**: Feed a 60 Hz loud/silent alternation through the envelope with injected frame
times and count transitions per area; lay out at portrait, landscape and tiny sizes.

**Acceptance Scenarios**:

1. **Given** a loud/silent alternation at 60 Hz with a thick line, **When** drawn with Reduce flashing on, **Then** no area has more transitions per window than the budget (and likewise with it off).
2. **Given** any output size, **When** laid out, **Then** every point lies inside the largest inscribed circle.

### Edge Cases

- Fewer samples than the window (just after start): missing samples read 0 (the base circle).
- NaN or infinite samples: treated as 0.
- Output size 0: nothing drawn; tiny sizes give valid geometry.
- Pause and resume: the gain starts afresh.
- Ring or amplitude changed while running: applies from the next frame without rebuilding the generator.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-005-R1**: The radial waveform MUST be a native visual under VIS-001's generator contract and the shared host contract, drawn by the shared flat-triangle pass; its input is VIS-003's mono sample history (oldest first).
- **VIS-005-R2**: Geometry: the window is the newest N = 1,024 samples; point i (oldest first) lies at angle θᵢ = 2π·i/N clockwise from the top, at radius rᵢ = R₀ + A·sᵢ, where sᵢ is the signed, gain-normalized sample in −1…1; R₀ and A are fractions of half the output's shorter side. Positive samples push outward, negative samples pull inward.
- **VIS-005-R3**: Closure: the ring is a closed polyline of N segments; segment N − 1 joins the newest point back to the oldest.
- **VIS-005-R4**: No seam: the last k = 256 points of the window are crossfaded (raised-cosine weights) into the k samples that precede the window, so the newest point continues smoothly into the oldest. A constant input stays constant (the weights sum to 1).
- **VIS-005-R5**: Gain: VIS-004's automatic gain (level = window peak |s| with hold and release, floor 0.01; frame-duration driven, deterministic). Silence (window peak below 0.0001) gives sᵢ = 0: the base circle is drawn.
- **VIS-005-R6**: Settings: Ring Small / Medium / Large (R₀ = 0.40 / 0.55 / 0.70, default Medium) and Amplitude Low / Medium / High (A = 0.10 / 0.18 / 0.25, default Medium); every radius stays within 0.15…0.95 of half the shorter side.
- **VIS-005-R7**: Drawing: line thickness 0.6 % of the shorter side (at least 1 px), segment k in palette color k of N (oldest to newest, ACC-003-R13), premultiplied over an opaque black background.
- **VIS-005-R8**: Flash safety: every frame passes FX-019's envelope with the 17-area model built from the ring's segments (FX-019-R4, R9, FX-001-R10), as the other native visuals.
- **VIS-005-R9**: The app MUST offer "Radial Waveform" as a Visual choice (stored `radialWaveform` under `settings.visual`) with Ring (`settings.radialWaveform.ring`: `small`/`medium`/`large`, anything else → medium) and Amplitude (`settings.radialWaveform.amplitude`: `low`/`medium`/`high`, anything else → medium). Glow shared, Bars hidden. Switching does not restart the audio source; lifecycle and fallback are VIS-001-R12 to R16's. Both keys are FR-065 user settings, in the FILE-005 backup policy and the device privacy allow list, and are reset by `-uitestResetNotice`.
- **VIS-005-R10**: Scene capture records the radial waveform as no native layer (as VIS-003-R12).
- **VIS-005-R11**: Accessibility (FR-070): one element labeled "Radial Waveform visualization", identifier `radialWaveform`, value naming the ring, the amplitude and the glow (for example "Medium ring, Medium amplitude, Glow off"); each new control has a stable identifier.
- **VIS-005-R12**: Golden images of a sine ring and of silence MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator), with the record policy and integrity check.
- **VIS-005-R13**: The other native visuals MUST NOT change: their tests pass unchanged.
- **VIS-005-R14**: Real-time safety (Constitution VII): layout, tessellation and area levels allocate nothing per frame.
- **VIS-005-R15**: The radial waveform has no persistence or afterglow, so ACC-012's persistence caps do not apply; the safety clamp still reaches it through the glow and the flash envelope like the other native visuals.

### Key Entities

- **Radial waveform configuration**: base radius R₀, amplitude A, line thickness, palette, background.
- **Gain state**: VIS-004's level and the time since the last rise.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-005-S1**: For sines whose period does not divide the window, at several phases, the largest neighbour distance (closing segment included) ≤ 1.5 × the median; without the seam treatment it exceeds 5 × the median.
- **VIS-005-S2**: DC +0.5 → every radius > R₀; DC −0.5 → every radius < R₀; silence → every radius = R₀ (spread 0 within 1e-12).
- **VIS-005-S3**: A steady fixture gives bit-identical points on 10 successive frames.
- **VIS-005-S4**: The 60 Hz loud/silent alternation stays within the transition budget with Reduce flashing on and off.
- **VIS-005-S5**: The sine ring and silence pass their goldens on the macOS host and the iOS Simulator.
- **VIS-005-S6**: One UI test of at most 30 s chooses Radial Waveform and a ring size with the source started once; the setting keys persist (unit test).
- **VIS-005-S7**: Every existing VisualGenerators and RenderGoldens test passes; the package builds in the Linux shape.

## Assumptions

- The audio is the normalized ring's 44.1 kHz analysis tap mixed to mono by VIS-003's tap.
- Simulator results are not device evidence; frame time on devices is `{device}` work.
- No new stored data besides the two setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual.
