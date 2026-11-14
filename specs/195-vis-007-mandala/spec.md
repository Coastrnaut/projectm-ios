# Feature Specification: VIS-007 Mandala Symmetry

**Feature Branch**: `feature/vis-007` (spec directory `195-vis-007-mandala`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (device task VIS-007-T13 open)

**Input**: User description: "Implement VIS-007 (Mandala symmetry) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Repeat parameterized shapes with selectable rotational symmetry."
Acceptance, verbatim: "Changing symmetry from 4 to 8 doubles repeated sectors deterministically." P1, L,
depends on ANL-002 (integrated). Mirror the native visuals VIS-004, VIS-005 and VIS-006; the shapes go
through FX-019's flash envelope and respect ACC-012's caps."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-007-R1…`, success criteria `VIS-007-S1…`, tasks `VIS-007-T01…`. Requirements of
other features are cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility),
FR-072 (Reduce flashing); ACC-001 (Reduce Motion); VIS-001-R1, R10, R12 to R16 (native visual contract,
Reduce flashing slew, lifecycle, fallback); VIS-003-R12 (scene capture); VIS-005-R12 (generator goldens);
ANL-002 (log-frequency bands), ANL-003 (smoothing); FX-001-R10 (glow and flash safety); FX-019-R4, R9,
R11 (strobe safety envelope); ACC-003-R13 (palette); ACC-012 (sensory safety clamp); QA-002 / QA-003
(golden images, image diff).

## Baseline: what exists today (audit of 2026-11-14, commit `4157fa8f`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 to VIS-006 in `Packages/VisualGenerators`: CPU geometry implementing the flash region model, flat triangles drawn by the shared flat-shape pass, one host with one frame loop, glow, capture and recording. | No visual repeats a shape with rotational symmetry. |
| Bands | ANL-002's 16 to 128 log-frequency bands reach every band-driven native visual each frame, smoothed by ANL-003 and slewed by VIS-001-R10 under Reduce flashing. | The mandala reads the same bands. |
| Flash safety | FX-019's envelope over 17 areas, fed by any flat region layout; ACC-012's profile reaches the generators through the frame context. | The mandala's regions feed the same model. |
| Motion | ACC-001's Reduce Motion reaches the app's UI animation policy; no native visual moves on its own today. | A rotation that respects Reduce Motion. |
| Choosing a visual | Settings → Visual lists one row per visual choice; native visuals show their options and Glow. | A new choice and its options. |
| Golden images | VIS-003 to VIS-006 keep generator-level goldens per platform class. | One golden at 6-fold symmetry. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the
conservative, local-first option.

- Q: Which shape is repeated, and how do the bands drive it? → A: One petal per sector, a strip of 12 flat quads from the centre outward; the low group sets its length, the mid group its width, the high group a curl of its centre line, the overall energy its brightness. Three groups (not every band) keep the shape readable at any bar count and make the result independent of the band count's parity. Rejected: one petal per band (the shape would change with the Bars setting, which does not apply to this visual); free-form polygons (not convex quads, so outside the shared flash region model) (VIS-007-R2, R3).
- Q: Which symmetries, and what does Mirror mean? → A: N ∈ {3, 4, 5, 6, 8, 12}, default 6 (the classic hexagonal mandala). Mirror off: cyclic symmetry, one petal centred in each sector, which may curl to one side. Mirror on: dihedral symmetry, the petal is drawn in the first half of each sector and reflected across the sector's centre line, so each sector holds two petals; Mirror off by default so the default picture has the fewest regions. Petals always stay inside their sector (or half-sector), so copies never overlap and the flash model's area count is exact. Rejected: any integer N (more settings states, tiny sectors at high N); overlapping petals (double-counted light) (VIS-007-R3, R4).
- Q: Rotation speed, cap and Reduce Motion? → A: A fixed slow turn, 0.025 turns per second (one turn in 40 s), clockwise; any configured speed is capped at 0.05 turns per second; Reduce Motion (ACC-001's system setting) halves it. A speed change re-anchors the angle at that frame, so the figure never jumps. No user speed setting (the brief asks for a small set). Rejected: stopping the rotation under Reduce Motion (the brief asks for halving; the speed is already slow); a pure function of time without re-anchoring (a visible jump when Reduce Motion toggles) (VIS-007-R5, R6).
- Q: Colour and brightness? → A: Palette colour by step along the petal (12 steps of the active palette, centre outward), identical in every sector so colour preserves the symmetry; alpha 0.5 + 0.3·overall energy, at most 0.8 (ACC-012's brightness cap, as VIS-006's rings), so silence still shows the base shape. Rejected: colour per sector (breaks the visual symmetry); full-white peaks (VIS-007-R7).
- Q: Which settings? → A: Three: Symmetry (segmented 3/4/5/6/8/12, stored as Int, anything else → 6), Mirror (toggle, Bool, default off) and Petal style (segmented Petal/Round/Spike, stored as a string, anything else → Petal). Rejected: band-group sliders and a speed slider (more keys, more motion risk) (VIS-007-R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose a mandala and its symmetry (Priority: P1)

A user playing music opens Settings, chooses the visual "Mandala" and sees petals repeated around the
centre, growing and widening with the music and turning slowly. The user picks how many times the shape
repeats (3, 4, 5, 6, 8 or 12), whether each repeat is mirrored, and the petal style. The choices are
remembered.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose Mandala in Settings, check that Symmetry, Mirror and Petal
are offered and Bars is not, change the symmetry, close Settings and check that the visual is shown and
its value names the symmetry.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Mandala", **Then** it replaces the current visual without restarting the audio source.
2. **Given** Mandala chosen, **When** Settings is open, **Then** Symmetry (6 selected by default), Mirror (off), Petal style and the Glow controls are offered and Bars is not.
3. **Given** a symmetry, mirror and petal style chosen, **When** the app is relaunched, **Then** they are restored.

---

### User Story 2 - Symmetry is exact and deterministic (Priority: P1)

Whoever checks the visual feeds the same band values and time at 4-fold and at 8-fold symmetry and finds
twice as many repeated sectors, each an exact rotated copy of the first, and the same result every run.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Lay out fixed bands at a fixed time at N = 4 and N = 8 and compare sector counts,
drawn shape counts and every sector's points with the first sector's rotated points; repeat the run.

**Acceptance Scenarios**:

1. **Given** fixed bands and time, **When** laid out at 4-fold and at 8-fold symmetry, **Then** the sector count goes from 4 to 8 and the drawn vertex count doubles exactly.
2. **Given** either layout, **When** each sector k is compared with sector 0 rotated by 2πk/N about the centre, **Then** every point matches within 1e-9 of a pixel.
3. **Given** the same inputs laid out again, **When** compared, **Then** the geometry is bit-identical.
4. **Given** Mirror on, **When** each sector is inspected, **Then** its second half is the first half reflected across the sector's centre line, and the sector count is unchanged.
5. **Given** a 6-fold mandala rendered offscreen, **When** compared with the committed golden, **Then** it passes QA-002's rule.

---

### User Story 3 - Safe motion and light (Priority: P1)

The mandala reacts to every band and turns on its own, so it must not become a flashing or fast-spinning
pattern. However loud and sudden the music, the picture stays within the strobe envelope; the rotation
never exceeds a fixed slow speed, and with Reduce Motion on it turns at half that speed.

**Independent Test**: Feed bands that jump between silence and full scale on every frame with injected
frame times through the envelope and count transitions per area; measure the rotation angle against the
injected clock with Reduce Motion off and on.

**Acceptance Scenarios**:

1. **Given** bands alternating silence and full scale on every frame at 60 Hz, **When** drawn with Reduce flashing on and off, with and without the strongest glow, **Then** no area has more transitions per window than the budget.
2. **Given** any configured speed, **When** the angle is measured over 10 s of injected time, **Then** it never turns faster than the cap; with Reduce Motion on, exactly half the speed.
3. **Given** Reduce Motion toggled while running, **When** the next frame is laid out, **Then** the angle continues from where it was (no jump).

### Edge Cases

- Silence (all bands 0, or no bands yet): the base shape (shortest, narrowest petals, dimmest brightness), still turning slowly.
- Bands above 1, negative or not finite: read as 1, 0 and 0.
- Fewer than 3 bands: missing groups read 0.
- An unsupported symmetry value (stored or set): read as 6.
- Output size 0: nothing drawn; tiny sizes give valid geometry.
- Pause and resume: the envelope history is kept (FX-019-R11); the rotation continues from the clock.
- Symmetry, mirror or petal changed while running: applies from the next frame without rebuilding the generator.
- Time going backwards (a test or a clock reset): the angle is still a function of the time; no crash.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-007-R1**: The mandala MUST be a native visual under VIS-001's generator contract and the shared host contract, drawn by the shared flat-triangle pass, driven by ANL-002's bands as smoothed by ANL-003 and slewed under Reduce flashing (VIS-001-R10).
- **VIS-007-R2**: Band groups: the band vector is split into three equal groups (low, mid, high; the remainder goes to high); each group's energy is its mean, clamped to 0…1 (non-finite reads 0). The overall energy is the mean of the three.
- **VIS-007-R3**: Shape: one petal per sector (two with Mirror), a strip of 12 steps from the inner radius 0.08 to the tip radius ℓ = 0.35 + 0.55·low of half the output's shorter side; its widest half-width is w = 0.2 + 0.4·mid of half the sector angle, shaped along the petal by the petal style's profile (Petal sin(πt), Round √sin(πt), Spike 1 − t); its centre line curls toward the sector's leading edge by 0.35·high·t² of half the sector angle. The petal stays inside its sector (or half-sector with Mirror).
- **VIS-007-R4**: Symmetry: N ∈ {3, 4, 5, 6, 8, 12} (default 6; anything else reads 6). Sector k is sector 0 rotated by 2πk/N about the centre. Mirror (default off) draws the petal in the first half-sector and its reflection across the sector's centre line in the second (dihedral symmetry); without Mirror the petal is centred in the sector (cyclic symmetry).
- **VIS-007-R5**: Rotation: the whole figure turns clockwise at 0.025 turns per second (one turn per 40 s). Configured speeds are capped at 0.05 turns per second; with Reduce Motion on (ACC-001) the speed is halved. A speed change keeps the angle continuous at the frame it happens.
- **VIS-007-R6**: Determinism: the geometry at a frame is a pure function of the band values, the configuration, the frame's injected time and the times at which the speed changed; no wall clock is read.
- **VIS-007-R7**: Drawing: each step of a petal is a flat quad in palette color (step mod 12) of 12, from the centre outward (ACC-003-R13), with alpha 0.5 + 0.3·overall energy (at most 0.8, below full white: ACC-012), premultiplied over an opaque black background.
- **VIS-007-R8**: Flash safety: every frame passes FX-019's envelope with the 17-area model built from the mandala's quads (FX-019-R4, R9, FX-001-R10), as the other native visuals.
- **VIS-007-R9**: The app MUST offer "Mandala" as a Visual choice (stored `mandala` under `settings.visual`) with Symmetry (`settings.mandala.symmetry`, Int, one of 3, 4, 5, 6, 8, 12; anything else → 6), Mirror (`settings.mandala.mirror`, Bool, default off) and Petal (`settings.mandala.petal`: `petal`/`round`/`spike`, anything else → petal). Glow shared, Bars hidden. Switching does not restart the audio source; lifecycle and fallback are VIS-001-R12 to R16's. The keys are FR-065 user settings, in the FILE-005 backup policy and the device privacy allow list, and are reset by `-uitestResetNotice`.
- **VIS-007-R10**: Scene capture records the mandala as no native layer (as VIS-003-R12).
- **VIS-007-R11**: Accessibility (FR-070): one element labeled "Mandala visualization", identifier `mandala`, value naming the symmetry, mirror, petal style and glow (for example "6-fold, Mirror off, Petal, Glow off"); each new control has a stable identifier.
- **VIS-007-R12**: A golden image of a 6-fold mandala MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator), with the record policy and integrity check.
- **VIS-007-R13**: The other native visuals MUST NOT change: their tests pass unchanged.
- **VIS-007-R14**: Real-time safety (Constitution VII): layout, tessellation and area levels allocate nothing per frame.

### Key Entities

- **Mandala configuration**: symmetry N, mirror, petal style, rotation speed, Reduce Motion, palette, background.
- **Rotation anchor**: the time and angle at which the current speed took effect.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-007-S1**: The same bands and time at N = 4 and N = 8 give 4 and 8 sectors, a vertex count that doubles exactly, and every sector equal to sector 0 rotated by 2πk/N within 1e-9; a repeated run is bit-identical.
- **VIS-007-S2**: With Mirror on, every sector's second half equals its first half reflected across the sector's centre line within 1e-9, and the drawn vertex count is twice that without Mirror.
- **VIS-007-S3**: Silence gives the base shape: tip radius 0.35, widest half-width 0.2 of half the sector angle, no curl, alpha 0.5.
- **VIS-007-S4**: Bands alternating silence and full scale on every frame at 60 Hz stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow.
- **VIS-007-S5**: The rotation never exceeds 0.05 turns per second; with Reduce Motion on it is exactly half the configured speed; a speed change keeps the angle continuous.
- **VIS-007-S6**: The 6-fold picture passes its golden on the macOS host and the iOS Simulator.
- **VIS-007-S7**: One UI test of at most 30 s chooses Mandala and changes the symmetry with the source started once; the setting keys persist (unit test).
- **VIS-007-S8**: Every existing VisualGenerators and RenderGoldens test passes; the package builds in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis pipeline (ANL-002), which already runs while a native visual is shown.
- Simulator results are not device evidence; frame time on devices is `{device}` work.
- No new stored data besides the three setting keys; no network; the privacy manifest does not change.
- projectM stays the default visual.
