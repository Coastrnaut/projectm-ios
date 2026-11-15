# Feature Specification: VIS-015 Tunnel Warp

**Feature Branch**: `feature/vis-015` (spec directory `263-vis-015-tunnel-warp`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-015 (Tunnel warp) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Render a depth-like tunnel with beat-synced speed." Acceptance, verbatim: "Tempo mapping changes
speed and zero BPM falls back smoothly." P1, depends on ANL-005 (tempo estimate, integrated). Keep the projectM
backend isolated; follow the shader policy."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-015-R1…`, success criteria `VIS-015-S1…`, tasks `VIS-015-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-003-R13 (palette), ACC-012
(brightness below full white); VIS-001-R12 to R16 (native visual contract); VIS-003-R12 (scene capture); VIS-007 (band
groups); VIS-013 (noise field, shared seeded noise, reviewed compile site ADR-0066); VIS-014 (kaleidoscope, a mode of
the same generator); ANL-005 (tempo estimate); SHOW-011 (tap tempo and the tempo snapshot); SHOW-010 (beat grid);
FX-019 (strobe safety envelope); QA-002 (golden images); FILE-005 (settings backup policy).

## Baseline: what exists today (audit of 2026-11-14, commit `daa43bc9`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Noise field (VIS-013) / Kaleidoscope (VIS-014) | One generator with two fragment entry points (plain, folded), pipelines built lazily per mode, SHD-006 seeded noise, an 8 × 8 CPU flash estimate, band-driven drive on the injected frame clock. | No polar depth mapping; motion is a fixed drift, not tempo-driven. |
| Tempo (ANL-005, SHOW-011) | `TempoSnapshot`: manual tap tempo first, else an estimate with confidence ≥ 0.5 in 60…200 BPM, else none. MOD-009 already reads it per frame in the native host (`lfoTempoBPM`). | No visual moves at the tempo. |
| Beat grid (SHOW-010) | Phase of the beat for quantised cues. | Not used by any native visual's motion. |
| Effects chain (FX-020) | Bloom only. | No tunnel or polar warp effect. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: What is the tunnel, and where does it live? → A: A third mode of VIS-013's noise field generator (beside plain and VIS-014's kaleidoscope), with its own fragment entry point and lazily built pipeline in the same reviewed compile site (ADR-0066), so no new compile site and no ADR. Each pixel at radius r and angle θ from the frame centre (the shorter side spans −0.5…0.5) maps to u = θ / 2π around the tunnel and depth v = 0.5 / r + phase. The wall is a ring pattern (one bright band per unit of depth) times a texture of SHD-006's seeded noise over (u, v), coloured by the palette and darkened by depth fog towards the centre. Rejected: a projectM preset (backend isolated); an image texture (needs sampling and edge handling); a new generator (second compile site) (VIS-015-R1, R2, R3).
- Q: How is the noise texture kept seamless around the tunnel and as depth wraps? → A: The texture is two octaves of value noise at 8 and 16 cells around, blended across the angle cut (u = 0 and u = 1 sample the same cells), so no seam at ±π; the lattice repeats every 4096 cells in depth (integer lacunarity 2), and the phase wraps every 4096 rings, so the wrap is invisible. Rejected: noise on the direction circle only (no depth detail) (VIS-015-R3).
- Q: How does tempo map to speed? → A: Speed is in rings per second: rings per beat × BPM / 60. "Pace" offers ½, 1 (default) or 2 rings per beat. The BPM is SHOW-011's tempo snapshot (manual tap first, else the ANL-005 estimate at confidence ≥ 0.5), read once per frame; the drive also refuses a BPM that is not finite, ≤ 0, or comes with confidence below 0.5. So 120 BPM moves exactly twice as fast as 60 BPM. Rejected: snapping the phase to the beat grid (SHOW-010) — it makes jumps when the grid's anchor moves; follow-up only if a device test asks for it (VIS-015-R4).
- Q: What happens with no tempo (zero BPM, tempo lost, low confidence)? → A: The target falls back to a base speed of 1.5 rings/s × pace (a 90 BPM equivalent). Every change of target — tempo appears, changes or is lost — is reached through one-pole smoothing with τ = 0.5 s of frame time (frame time clamped to 0…0.25 s), and the position is integrated as phase += speed · dt, so neither speed nor position ever jumps. The first frame after a start takes its target directly (nothing to be continuous with). Rejected: holding the last tempo (stale), stopping (looks broken) (VIS-015-R5).
- Q: How is it kept safe? → A: (a) Speed is capped at 3 rings/s: at any pixel the ring pattern then alternates at most 3 times per second, WCAG's general flash limit, at every tempo and pace (2 rings per beat at 120 BPM caps at 3); (b) bass punch: brightness 0.5 + 0.3 × the low group, smoothed (attack τ 0.08 s, release τ 0.3 s), never above 0.8 (ACC-012); (c) the frame passes the FX-019 envelope over 17 areas from a CPU mirror at 64 points, as VIS-013; (d) Reduce Motion halves the speed (after the cap) and halves the bass punch. Rejected: a speed punch on beats (abrupt motion) (VIS-015-R6, R7, R8).
- Q: Which controls and keys? → A: One setting, Pace (`settings.tunnel.pace`: `half`, `beat` or `double`; anything else → `beat`). Seed, palette and glow: the seed is VIS-013's default 1301 (fixed); palette and glow are shared; Bars hidden. Accessibility: identifier `tunnel`, label "Tunnel visualization", value "1 ring per beat, Glow off". Rejected: a free speed slider (tempo is the speed; one more unsafe range to cap) (VIS-015-R9, R12).

- Q: The tempo snapshot updates only every 250 ms (SHOW-011's poll); does the tunnel need a faster tempo feed? → A: No. The host reads the snapshot once per frame; a new value is a step in the target that the 0.5 s speed smoother turns into a smooth ramp, and the phase never depends on the tempo directly. While the tunnel is shown the tempo analysis follows the tunnel's own analysis pipeline, as for every native visual (SHOW-011-D3) (VIS-015-R4, R5).
- Q: Is the pace saved in scenes or the show's scene snapshot? → A: No, as VIS-013 and VIS-014: the tunnel is no SCN-001 layer kind; a scene captured while it is shown records no native layer, and the pace is a user setting in the FILE-005 backup only (VIS-015-R9, R11).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A tunnel that moves with the beat (Priority: P1)

A user chooses "Tunnel" and flies down a softly textured, coloured tunnel whose rings come towards them at the
music's tempo: one ring per beat by default. When they tap a faster tempo, the tunnel speeds up smoothly.

**Why this priority**: It is the roadmap row and the first half of its acceptance.

**Independent Test**: Drive the tunnel's motion with an injected clock and tempo; compare settled speeds at 60 and
120 BPM; check the position is continuous at a tempo change.

**Acceptance Scenarios**:

1. **Given** a tempo of 120 BPM, **When** the speed has settled, **Then** it is exactly twice the settled speed at 60 BPM.
2. **Given** the tempo changes from 60 to 120 BPM, **When** frames are drawn, **Then** the position never jumps: each frame advances by speed × frame time and the speed changes by a bounded amount per frame.
3. **Given** a fixed time, tempo and band timeline, **When** rendered, **Then** it matches the committed golden image (macOS host and iOS Simulator), and two renders are identical.

---

### User Story 2 - No tempo falls back smoothly (Priority: P1)

When there is no tempo — silence, the estimate is unsure, or the user resets the tap tempo — the tunnel keeps
moving at a calm base speed, easing there without a jerk.

**Independent Test**: Settle at 120 BPM, then set the tempo to 0, to none, or to a low-confidence estimate; check
the speed eases to the base speed with a bounded change per frame, no NaN and no jump in position.

**Acceptance Scenarios**:

1. **Given** 120 BPM settled, **When** the BPM becomes 0, **Then** speed eases to the base speed, each frame's change bounded, never NaN.
2. **Given** no tempo from the start, **When** drawn, **Then** it moves at the base speed.
3. **Given** an estimate with confidence below 0.5, **When** drawn, **Then** it is treated as no tempo.

---

### User Story 3 - Safe and calm when asked (Priority: P1)

Bass makes the tunnel glow brighter but it never flashes; Reduce Motion slows it.

**Acceptance Scenarios**:

1. **Given** any tempo and pace, **When** drawn, **Then** the speed never exceeds 3 rings per second.
2. **Given** bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
3. **Given** Reduce Motion on, **When** settled, **Then** the speed is half.

---

### User Story 4 - Choose and control it (Priority: P1)

The user chooses Tunnel in Settings, sets Pace, and it is remembered.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Tunnel, **Then** it replaces the visual without restarting the audio source.
2. **Given** a pace chosen, **When** the app is relaunched, **Then** it is restored.
3. **Given** the pace changed while running, **When** the next frame is drawn, **Then** it applies without rebuilding the visual, and the speed eases to the new target.

### Edge Cases

- Output size 0: nothing drawn. Non-square outputs: the centre is the frame centre; the shorter side sets the scale.
- The centre pixel (r → 0): depth is clamped and the fog makes it dark; no NaN or infinity reaches the frame.
- The angle's cut at ±π: no seam (blended texture).
- BPM not finite, negative, zero or above any sensible tempo: not finite / ≤ 0 → no tempo; any tempo is capped by the 3 rings/s ceiling.
- Long frame gaps or time going backwards: at most 0.25 s of motion per frame, never backwards.
- Stored pace not one of the three: `beat`.
- Switching between Noise Field, Kaleidoscope and Tunnel: the same generator changes mode from the next frame; the other modes draw exactly as before (their recorded digests and goldens match).

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-015-R1**: The tunnel MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-015-R2**: It MUST be a mode of VIS-013's reviewed noise field generator with its own entry point; the plain field's and the kaleidoscope's frames MUST be unchanged.
- **VIS-015-R3**: Picture: depth v = 0.5 / r + phase, angle u = θ / 2π; rings (one per unit depth) × a seamless two-octave seeded-noise texture, palette colour, depth fog towards the centre. One shared module defines the mapping and texture for the shader (GPU text) and the flash estimate (CPU mirror); the GPU agrees with the CPU mirror.
- **VIS-015-R4**: Tempo mapping: target speed = pace (½, 1, 2 rings per beat) × BPM / 60 rings/s, BPM from the tempo snapshot (manual first, else an estimate with confidence ≥ 0.5); a BPM not finite or ≤ 0, or confidence < 0.5, counts as no tempo.
- **VIS-015-R5**: Smoothness: no tempo → base target 1.5 × pace rings/s; the speed follows its target with τ = 0.5 s of frame time (≤ 0.25 s per frame), the phase advances by speed × dt (never backwards), wraps every 4096 rings invisibly; the first frame after a reset takes the target directly.
- **VIS-015-R6**: Safety cap: speed ≤ 3 rings/s at any tempo and pace; brightness 0.5 + 0.3 × smoothed low group, ≤ 0.8.
- **VIS-015-R7**: Flash safety: every frame passes FX-019's envelope over all 17 areas from the CPU mirror at an 8 × 8 grid; no allocation per frame.
- **VIS-015-R8**: Reduce Motion (ACC-001): speed × 0.5 (after the cap) and bass punch × 0.5, from the next frame.
- **VIS-015-R9**: The app MUST offer "Tunnel" as a Visual choice (stored `tunnel` under `settings.visual`) with `settings.tunnel.pace` (`half`/`beat`/`double`; anything else → `beat`). Glow shared, Bars hidden. The key is an FR-065 user setting, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`. The host reads the tempo snapshot once per frame.
- **VIS-015-R10**: A golden image of the tunnel MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-015-R11**: Scene capture records the tunnel as no native layer (as VIS-003-R12).
- **VIS-015-R12**: Accessibility (FR-070): one element labeled "Tunnel visualization", identifier `tunnel`, value "1 ring per beat, Glow off"; the Pace control has a stable identifier.
- **VIS-015-R13**: The other native visuals MUST NOT change behaviour: their tests pass; the package builds in the Linux shape.

### Key Entities

- **Tunnel tempo**: BPM (optional) and confidence; valid or not.
- **Tunnel pace**: rings per beat (½, 1, 2).
- **Tunnel drive**: smoothed speed (rings/s), smoothed brightness, phase (rings, wrapped).
- **Noise field configuration**: VIS-013's, plus the tunnel pace (0 = not a tunnel).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-015-S1**: Settled speed at 120 BPM equals 2 × the settled speed at 60 BPM (relative error ≤ 1e-6).
- **VIS-015-S2**: Across a tempo change and a fallback to no tempo, every frame's position advance equals speed × frame time, the per-frame speed change is ≤ |target − speed| × (1 − e^(−dt/0.5)), and no value is NaN.
- **VIS-015-S3**: The speed never exceeds 3 rings/s for any tempo 0…1000 BPM and pace; half with Reduce Motion.
- **VIS-015-S4**: Bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-015-S5**: The tunnel's golden passes on the macOS host and the iOS Simulator; the noise field's and kaleidoscope's digests and goldens are unchanged.
- **VIS-015-S6**: One UI test of at most 30 s chooses Tunnel with the source started once; the setting persists (unit test); the key is in every list.
- **VIS-015-S7**: Every existing native visual and golden test passes; the package builds in the Linux shape.

## Assumptions

- Tempo comes from SHOW-011's snapshot (which applies ANL-005's confidence floor and range); bands from the native host's own analysis (ANL-002).
- Simulator results are not device evidence; the frame rate and look on D1 are `{device}` work.
- One new setting key; no new catalog parameter; no network; the privacy manifest does not change.
- projectM stays the default visual.
- The reviewed compile site (`NoiseFieldGenerator.swift`, ADR-0066) gains the tunnel function from a module constant; no new compile site, so no new ADR (recorded here instead).
