# Feature Specification: VIS-014 Kaleidoscope Field

**Feature Branch**: `feature/vis-014` (spec directory `259-vis-014-kaleidoscope-field`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-014 (Kaleidoscope field) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Mirror source image around adjustable wedge count." Acceptance, verbatim: "Wedge
count changes output symmetry without visible seams." P1, depends on ANL-002 (normalized bands, integrated). Keep
the projectM backend isolated; follow the shader policy."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-014-R1…`, success criteria `VIS-014-S1…`, tasks `VIS-014-T01…`. Other features are
cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion),
ACC-003-R13 (palette), ACC-012 (brightness below full white); VIS-001-R12 to R16 (native visual contract); VIS-003-R12
(scene capture); VIS-007 (band groups, the mandala); VIS-013 (noise field, shared seeded noise, ADR-0066); ANL-002
(normalized bands); FX-019 (strobe safety envelope); QA-002 (golden images); FILE-005 (settings backup policy).

## Baseline: what exists today (audit of 2026-11-14, commit `e6a8b6d2`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Effects chain (FX-020) | Bloom only; `fx.kaleidoscope` appears only as an *unknown* entry in FX-020's round-trip test. | No kaleidoscope or mirror effect exists to reuse. |
| Mandala (VIS-007) | Repeats a flat petal 3…12 times with optional mirror; geometry, not an image. | Its symmetry is built from quads; it does not fold a picture. |
| Noise field (VIS-013) | A full-screen procedural field from SHD-006's seeded noise, band-driven warp and brightness, drift on the frame clock, an 8 × 8 CPU flash estimate, the tenth reviewed Metal compile site (ADR-0066). | Not folded; no symmetry. |
| Camera mirror (CAM) | Horizontal flips of the camera picture. | Not a wedge fold. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: What is the source image that gets mirrored? → A: VIS-013's seeded noise field, folded. The kaleidoscope is a fold mode of the noise field's existing generator: every pixel's position is folded into one wedge before the noise is evaluated there, so the source is the drifting, band-warped noise field (fixed: 4 cells across the shorter side, 4 octaves, seed 1301). The fold math lives in one shared module (a CPU mirror and the GPU function text), used by the generator's shader and its flash estimate. No new Metal compile site and no new pipeline. Rejected: projectM's output as the source (the projectM backend stays isolated; a layer effect would need the compositor in the native visual path); a texture of a spectrum (sampling a texture needs edge handling at the wedge border, a seam risk); a separate generator (a second compile site for the same field) (VIS-014-R2, R3).
- Q: What does "wedge count" mean, and are odd counts allowed? → A: N is the rotational order, 2…24, every integer, default 6. Each of the N wedges (2π/N wide) is mirrored about its centre line, so the picture has N rotations and N mirror axes (2N mirror-image slices) for every N; odd counts are as symmetric as even ones because each wedge is folded within itself, never alternated with its neighbour. Rejected: even-only counts with alternate wedges mirrored (halves the choices and needs N even for continuity) (VIS-014-R4).
- Q: How does the kaleidoscope turn, and how is that kept safe? → A: The whole pattern turns at 0.1 rad/s plus up to 0.3 rad/s × the smoothed low (bass) group, never faster than 0.4 rad/s; Reduce Motion halves it (and, as the noise field, halves the drift and band warp). The angle advances on the injected frame clock, at most 1 s of turning per frame, never backwards; the bass smoother uses τ = 0.25 s of frame time. Rejected: beat-triggered jumps (abrupt motion); a user speed control (one more key, small value) (VIS-014-R5, R8).
- Q: How is "without visible seams" guaranteed and tested? → A: The fold is computed per pixel from the polar angle with a floor-based modulo and an absolute-value reflection, `|mod(θ − rotation, 2π/N) − π/N|`, which is continuous across every wedge boundary and every mirror axis, and the source is evaluated procedurally at the folded point (no texture, so no clamp-to-edge line). The GPU test measures, on the rendered frame, the difference across each wedge boundary and mirror axis (and the boundary pixel against its neighbours' mean), and requires it to be no larger than the interior neighbour difference at the same radius. A CPU test proves the fold continuous at every boundary for several N. Rejected: blurring the boundary (hides a seam instead of preventing it) (VIS-014-R6, S2).
- Q: Which controls and keys? → A: One setting, Wedges (2…24, default 6), stored as `settings.kaleidoscope.wedges` (Int; anything else → 6); palette and glow shared with the other native visuals, Bars hidden. Accessibility: identifier `kaleidoscope`, label "Kaleidoscope visualization", value "6 wedges, Glow off". Rejected: exposing the source's frequency, octaves and seed (they already belong to Noise Field) (VIS-014-R9, R12).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A seamless kaleidoscope (Priority: P1)

A user chooses "Kaleidoscope" and sees soft clouds of colour mirrored into a symmetric pattern around the centre,
slowly turning and flowing. They choose how many wedges it has; the symmetry changes and no line ever shows where
two wedges meet.

**Why this priority**: It is the roadmap row and its acceptance.

**Independent Test**: Render the kaleidoscope offscreen with N wedges; rotate the frame by one wedge and mirror it
across a wedge axis and compare; compare pixels on both sides of every wedge boundary; change N and check the
symmetry follows.

**Acceptance Scenarios**:

1. **Given** N wedges, **When** rendered, **Then** rotating the frame by 2π/N about the centre and mirroring it across a wedge's axis each map it onto itself within tolerance.
2. **Given** a different wedge count, **When** rendered, **Then** the frame has the new symmetry and not the old one.
3. **Given** any wedge count, **When** rendered, **Then** the difference across each wedge boundary is no larger than the difference between neighbouring pixels inside a wedge.
4. **Given** a fixed time and band timeline, **When** rendered, **Then** it matches the committed golden image (macOS host and iOS Simulator).

---

### User Story 2 - Music turns it, safely (Priority: P1)

Bass makes the kaleidoscope turn faster and swirl; loudness brightens it gently; it never flashes and never turns
faster than the cap.

**Independent Test**: Feed a band timeline and check the turning speed and brightness stay within their bounds and
follow the bass smoothly; feed bursts alternating with silence and check the strobe envelope.

**Acceptance Scenarios**:

1. **Given** silence, **When** drawn, **Then** it turns at 0.1 rad/s at brightness 0.5.
2. **Given** full bass, **When** settled, **Then** it turns at 0.4 rad/s, never faster; brightness never exceeds 0.8.
3. **Given** bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
4. **Given** Reduce Motion on, **When** drawn, **Then** it turns half as fast.

---

### User Story 3 - Choose and control it (Priority: P1)

The user chooses Kaleidoscope in Settings, sets Wedges, and it is remembered.

**Independent Test**: In the simulator, choose Kaleidoscope, check the Wedges control is offered and Bars is not,
change Wedges, close Settings and check the visual's value.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Kaleidoscope, **Then** it replaces the visual without restarting the audio source.
2. **Given** a wedge count chosen, **When** the app is relaunched, **Then** it is restored.
3. **Given** the wedge count changed while running, **When** the next frame is drawn, **Then** it uses the new count without rebuilding the visual.

### Edge Cases

- Output size 0: nothing drawn. Non-square outputs: the fold centre is the frame centre; the shorter side sets the scale.
- The centre pixel: every wedge meets there; the fold is continuous there (radius 0 maps to one point).
- The angle's wrap at ±π: invisible, because 2π is a whole number of wedges.
- Bands missing, not finite or outside 0…1: read as 0 or clamped (VIS-007's groups).
- A long frame gap or time going backwards: at most 1 s of turning per frame, never backwards.
- Stored wedge count outside 2…24 or not a number: 6.
- Switching between Noise Field and Kaleidoscope: the fold turns on or off from the next frame; Noise Field draws exactly as before.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-014-R1**: The kaleidoscope MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-014-R2**: The source image MUST be VIS-013's seeded noise field (4 cells, 4 octaves, seed 1301), drawn by the noise field's existing reviewed generator with the fold on; with the fold off the noise field's frames MUST be unchanged (its recorded digests still match).
- **VIS-014-R3**: The fold MUST come from one shared module (CPU mirror and GPU function text) used by both the shader and the flash estimate; the GPU fold agrees with the CPU mirror.
- **VIS-014-R4**: Wedge count N: every integer 2…24 (default 6); the picture has N-fold rotational symmetry and N mirror axes about the frame centre.
- **VIS-014-R5**: Turning: 0.1 rad/s + 0.3 rad/s × the smoothed low group (τ 0.25 s of frame time), at most 0.4 rad/s, on the frame clock (≤ 1 s per frame, never backwards); the source keeps VIS-013's drift, band warp and brightness (0.5…0.8, ACC-012).
- **VIS-014-R6**: No seams: the fold is continuous across every wedge boundary and mirror axis; the source is evaluated at the folded point without texture edges.
- **VIS-014-R7**: Flash safety: every frame passes FX-019's envelope over all 17 areas from the CPU mirror sampled at the folded points of an 8 × 8 grid; no allocation per frame.
- **VIS-014-R8**: Reduce Motion (ACC-001): turning × 0.5, plus VIS-013-R8 (drift and band warp × 0.5), from the next frame.
- **VIS-014-R9**: The app MUST offer "Kaleidoscope" as a Visual choice (stored `kaleidoscope` under `settings.visual`) with `settings.kaleidoscope.wedges` (Int 2…24, anything else → 6). Glow shared, Bars hidden. The key is an FR-065 user setting, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-014-R10**: A golden image of the kaleidoscope MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-014-R11**: Scene capture records the kaleidoscope as no native layer (as VIS-003-R12).
- **VIS-014-R12**: Accessibility (FR-070): one element labeled "Kaleidoscope visualization", identifier `kaleidoscope`, value "6 wedges, Glow off"; the Wedges control has a stable identifier.
- **VIS-014-R13**: The other native visuals MUST NOT change behaviour: their tests pass; the package builds in the Linux shape.

### Key Entities

- **Kaleidoscope fold**: wedge count and rotation angle; maps a point to its folded point in the first half-wedge.
- **Noise field configuration**: VIS-013's, plus the wedge count (0 = no fold).
- **Noise drive**: VIS-013's smoothed warp, brightness and drift, plus the smoothed bass spin and the rotation angle.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-014-S1**: For N = 5 and 6, the rendered frame rotated by 2π/N and mirrored across a wedge axis differs from itself by a mean of at most 1/255 per channel inside the inscribed circle; rotated by the other count's angle it differs by at least 4 times that.
- **VIS-014-S2**: Across every wedge boundary and mirror axis, the mean difference between the two sides, and between the boundary pixel and its neighbours' mean, is at most the mean interior neighbour difference at the same radii.
- **VIS-014-S3**: The settled turning speed is 0.1 rad/s for silence and 0.4 rad/s for full bass (within 1 %), half with Reduce Motion; brightness never exceeds 0.8.
- **VIS-014-S4**: Bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-014-S5**: The kaleidoscope's golden passes on the macOS host and the iOS Simulator; the noise field's digests and goldens are unchanged.
- **VIS-014-S6**: One UI test of at most 30 s chooses Kaleidoscope with the source started once; the setting persists (unit test); the key is in every list.
- **VIS-014-S7**: Every existing native visual and golden test passes; the package builds in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis pipeline (ANL-002).
- Simulator results are not device evidence; the frame rate on D1 is `{device}` work.
- One new setting key; no new catalog parameter; no network; the privacy manifest does not change.
- projectM stays the default visual.
- The noise field's reviewed compile site (`NoiseFieldGenerator.swift`, ADR-0066) gains the fold function from a module constant; no new compile site, so no new ADR is needed (recorded here instead).
