# Feature Specification: VIS-012 Reaction Diffusion

**Feature Branch**: `feature/vis-012` (spec directory `286-vis-012-reaction-diffusion`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement VIS-012 (Reaction diffusion) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Offer configurable seed patterns and bounded iteration counts." Acceptance, verbatim: "Preset
reload reproduces initial pattern and never writes NaN textures." P2, L, depends on ANL-002 (log-frequency bands,
integrated). Keep the projectM backend isolated; follow the shader policy."

Identifiers carry the roadmap ID: requirements `VIS-012-R1…`, success criteria `VIS-012-S1…`, tasks `VIS-012-T01…`.
Other features are cited by their own IDs: ANL-002 (bands), VIS-007 (band groups), VIS-011 (fluid ink, the template),
VIS-013 to VIS-015, VIS-020 (modes of the noise field generator, reviewed compile site ADR-0066), ACC-001 (Reduce
Motion), ACC-012 (nothing above 0.8), FX-019 (strobe safety envelope), PERF-009 (native pipeline archive), SHD-011
(reviewed Metal compile sites), QA-002 (golden images), FILE-005 (library backup settings policy), FR-065, FR-070.

## Baseline: what exists today (audit of 2026-11-15, commit `11bb4887`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Grid simulations (VIS-011) | Fluid Ink is the noise field generator's fifth mode: fixed textures made once, a 1/60 s fixed-step clock with ≤ 4 steps per frame and stall skip, an exponent-bit non-finite guard, a 16 × 16 health image read back without waiting, a CPU reference solver in the tests-only target `VisualFluidReference`. | No reaction-diffusion model, no seed patterns, no user-chosen iteration count. |
| Bands (ANL-002, VIS-007) | Every native generator receives the frame's bands; `MandalaBandGroups` gives low, mid and high. | Nothing turns bass into a grid injection. |
| Seeded content (VIS-013) | The noise field stores a seed (`settings.noiseField.seed`) and reproduces its pattern. | No stored seed pattern for a simulation's initial state. |
| Strobe safety (FX-019) | VIS-011 feeds the envelope a rigorous uniform upper bound (`loadUniform`). | No bound for a reaction-diffusion picture. |

## Clarifications

### Session 2026-11-15

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative, local-first
option.

- Q: Where does reaction diffusion live? → A: A sixth mode of the noise field generator ("Reaction Diffusion"), as VIS-011: its fragment functions are a module constant appended to the generator's reviewed shader source (ADR-0066 site, so PERF-009's archive key covers it), pipelines built lazily from that library. No new compile site, no compute pipeline, no ADR (VIS-012-R1, R10).
- Q: Which model and grid? → A: Gray–Scott on a fixed 128 × 128 torus (wrap-around edges) on every device: U and V in one two-channel 32-bit float texture pair; explicit Euler with dt = 1 and the 9-point Laplacian (centre −1, edges 0.2, corners 0.05); per iteration U += Du·∇²U − UV² + F(1 − U), V += Dv·∇²V + UV² − (F + k)V; then each value non-finite → 0 and clamped to [0, 1]. 128² keeps every preset's structures visible on a phone and costs 0.25 MiB (VIS-012-R3, R4).
- Q: Which presets and ranges? → A: Four named presets with Du = 1.0, Dv = 0.5: Coral (F 0.0545, k 0.062, the default), Mitosis (F 0.0367, k 0.0649), Spots (F 0.030, k 0.062), Maze (F 0.029, k 0.057). Parameters are clamped to F 0.01…0.10, k 0.04…0.07, Du 0.2…1.0, Dv 0.1…0.5 (Du·dt ≤ 1 keeps the diffusion a convex combination) (VIS-012-R2).
- Q: Which seed patterns and what does the seed change? → A: Four patterns over a base of U = 1, V = 0, each seeded region set to U = 0.5, V = 0.25: Centre square (side 0.16 of the grid, centre offset by up to ±0.08 from the seed), Random spots (10 discs of radius 0.02…0.05 at seeded positions in 0.1…0.9), Ring (radius 0.25, width 0.03, centre offset by up to ±0.08), Stripes (horizontal bands 2 cells thick every ⌊N/5⌋ rows, at a seeded phase). The seed is an integer 0…9999 (default 1); SplitMix64 over it gives every random choice. The initial texture is computed on the CPU in single precision and copied to the GPU (staging buffer made once), so GPU and CPU reference start bit-identical (VIS-012-R5, R6).
- Q: What is a reload, and what does it reset? → A: Entering the mode, a change of preset, pattern or seed, the host's loop restart, a health-check failure and a relaunch with the same stored settings all re-seed the grid from the stored pattern and seed; a Speed change does not (VIS-012-R6).
- Q: How are iterations bounded? → A: A fixed 1/60 s step on the frame clock, from an anchor in exact integer nanoseconds as VIS-011; each frame runs the steps that end by its time, at most 4, a longer stall skips the rest (counted). Each step runs Speed iterations (user setting 1…16, default 8; Reduce Motion runs ⌈Speed/2⌉). So a frame runs at most 64 iterations, enforced by the scheduler (VIS-012-R7).
- Q: How does audio act? → A: Bass (ANL-002 bands, VIS-007's low group) triggers injections: a kick fires when the low group rises above 0.6 after being below 0.4, at least 0.25 s after the last accepted one (1 s under Reduce Motion). The queue holds 4 (a full queue refuses, counted); a step applies at most 1. An injection is a Gaussian of radius 0.04 at a seeded position (seed, injection index) in 0.1…0.9 that adds 0.25 × bass × w to V and subtracts it from U, clamped to [0, 1]. Feed and kill are never modulated, so every preset stays in its stable range (VIS-012-R8).
- Q: How is a non-finite value handled? → A: Every pass maps a non-finite input to 0 by its exponent bits (immune to fast math) and clamps to [0, 1]. Each frame a 16 × 16 health image (per block: max U, max V, min of U and V, a flag for non-finite or out-of-range) is copied to one of three shared buffers and read without waiting once its command buffer completed; a flag re-seeds the grid on the next frame (counted). The CPU reference checks every value after every iteration (VIS-012-R9).
- Q: How is it drawn, and how does the strobe safety envelope see it? → A: The display maps t = smoothstep(0.1, 0.4, V) through 8 palette stops, times t, times a fade-in ramp that rises linearly from 0 to 1 over 1 s after every reload, times the envelope's gain, each channel capped at 0.8 (ACC-012). The envelope sees a rigorous uniform upper bound: per channel min(0.8, brightest palette stop) × ramp in all 64 of VIS-013's samples. A reload goes dark at once and returns over 1 s, so even rapid reloads cannot strobe (VIS-012-R11).
- Q: What does Reduce Motion change? → A: Half the iterations per step (rounded up) and at most one injection per second (VIS-012-R12).
- Q: Which app surface and keys? → A: Visual choice "Reaction Diffusion" (`settings.visual` = `reactionDiffusion`), host style `.reactionDiffusion(settings)` switching in place with the other noise-field modes, accessibility identifier `reactionDiffusion`, value "<Preset>, <Pattern>, seed <n>, speed <s>, Glow off/on". Options under the Visual list: Preset and Pattern pickers, Seed and Speed steppers. Four keys, all in `AppSettings.allKeys` and FILE-005's included keys (they are settings): `settings.reactionDiffusion.preset` (`coral`/`mitosis`/`spots`/`maze`, anything else → coral), `settings.reactionDiffusion.pattern` (`square`/`spots`/`ring`/`stripes`, else → square), `settings.reactionDiffusion.seed` (0…9999, else → 1), `settings.reactionDiffusion.speed` (1…16, else → 8). Palette and glow are shared, Bars hidden; scenes record no layer (VIS-012-R13, R14).

### Session 2026-11-15 (speckit-clarify)

- Q: Does a palette or Glow change re-seed the grid? → A: No: they change only the display; the simulation keeps its state (VIS-012-R6).
- Q: Does Reaction Diffusion subscribe to the analysis event bus like Fluid Ink? → A: No: it reads only the frame's bands (ANL-002), so the host needs no subscription; bass kicks are detected inside the generator on the frame clock (VIS-012-R8).
- Q: How strict is the GPU health check? → A: Strict: any non-finite value, any value above 1 or below 0 sets the flag (every pass clamps, so a flag can only mean a fault); the reference solver asserts the same after every iteration (VIS-012-R9).
- Q: What happens to queued injections at a reload? → A: The queue, kick detector, clock and injection index start over, so a reload with the same bass timeline replays exactly (VIS-012-R6, R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A growing pattern from a chosen seed (Priority: P1)

A user chooses "Reaction Diffusion", a preset (Coral, Mitosis, Spots, Maze) and a seed pattern. The pattern fades in
and grows organically from the seed shape; bass pulses plant new growth.

**Independent Test**: Render a preset from a pattern and seed on an injected clock and compare with a golden image.

**Acceptance Scenarios**:

1. **Given** a preset, pattern and seed, **When** the visual starts, **Then** the grid starts from exactly that pattern and grows.
2. **Given** a different seed with Random spots, **When** it starts, **Then** the spots are elsewhere.
3. **Given** bass hits, **When** they arrive, **Then** new growth starts at seeded points, at most one per step.

### User Story 2 - Reload reproduces, never corrupts (Priority: P1)

**Acceptance Scenarios**:

1. **Given** stored settings, **When** the visual is re-selected, the preset re-chosen, or the app relaunched, **Then** the initial pattern is bit-identical to the first time.
2. **Given** every preset at maximum speed with repeated strong bass for thousands of iterations, **When** checked, **Then** every value is finite and within [0, 1].
3. **Given** a non-finite value somehow reaches the grid, **When** detected, **Then** the grid re-seeds and drawing continues.

### User Story 3 - Bounded work, constant memory, safe light (Priority: P1)

**Acceptance Scenarios**:

1. **Given** any frame rate and Speed, **When** a frame runs, **Then** it runs at most 4 steps and 64 iterations.
2. **Given** minutes of frames, resizes, mode switches and reloads, **When** checked, **Then** the textures keep their count, identities and allocated size.
3. **Given** reloads and bass bursts, **When** the envelope measures the frames, **Then** it sees an upper bound of the light and no value exceeds 0.8.
4. **Given** Reduce Motion, **When** it runs, **Then** it grows half as fast and accepts at most one injection per second.

### User Story 4 - Choose and configure it (Priority: P2)

**Acceptance Scenarios**:

1. **Given** Settings, **When** the user picks Reaction Diffusion, a preset, a pattern, a seed and a speed, **Then** they are stored across launches and the accessibility value describes them.

### Edge Cases

- Output size 0: nothing drawn; the simulation keeps running.
- Output size changes: the grid is independent of it (no reset, no reallocation).
- Stored values out of range or of the wrong type: the defaults.
- A frame clock that goes backwards: nothing runs.
- Speed changed mid-run: applies from the next step, no re-seed.
- Palette or Glow changed: display only, no re-seed.
- Reload: queued injections and the kick detector start over.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-012-R1**: Reaction Diffusion MUST be a mode of the VIS-013 noise field generator, switchable in place; projectM is untouched.
- **VIS-012-R2**: Four named presets with clamped feed, kill and diffusion parameters.
- **VIS-012-R3**: A fixed grid independent of the output size, wrap-around edges.
- **VIS-012-R4**: Each iteration applies the Gray–Scott update; every stored value is finite and within [0, 1] after every iteration.
- **VIS-012-R5**: Four seed patterns; the seed decides every random choice.
- **VIS-012-R6**: A reload (mode entry, preset/pattern/seed change, loop restart, health failure, relaunch) reproduces the initial state bit for bit.
- **VIS-012-R7**: Iterations per frame are bounded: ≤ 4 fixed steps per frame, Speed (1…16) iterations per step, ≤ 64 per frame.
- **VIS-012-R8**: Bass injections are bounded in strength, count per step, queue size and spacing; parameters are never modulated.
- **VIS-012-R9**: Non-finite values are mapped to 0; a GPU health check and the reference solver detect any; detection re-seeds (counted).
- **VIS-012-R10**: No new Metal compile site; the shader is part of a reviewed site's source and PERF-009's archive key.
- **VIS-012-R11**: The FX-019 envelope sees an upper bound of the drawn light; drawn values never exceed 0.8; a reload fades in over 1 s.
- **VIS-012-R12**: Reduce Motion halves the iterations and spaces injections to ≥ 1 s.
- **VIS-012-R13**: The app offers the choice and its four persisted settings with accessibility identifier and value (FR-070); keys are listed for backup and erase (FILE-005).
- **VIS-012-R14**: Scenes record no layer; textures are made once and never per frame.
- **VIS-012-R15**: A golden image per platform class (macOS host, iOS Simulator) under QA-002's rule.

### Key Entities

- **Reaction settings**: preset, pattern, seed, speed (stored).
- **Grid state**: U and V on the fixed grid; step index and anchor; fade-in ramp.
- **Injection**: frame time, strength 0…1, seeded position.
- **Grid health**: max U, max V, min value, non-finite/out-of-range flag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-012-S1**: The initial state after two independent reloads (generator recreated; settings decoded from storage) is bit-identical on the GPU readback and equals the CPU reference; another seed differs.
- **VIS-012-S2**: Every preset at Speed 16 for 3 000 iterations at 128² with a strong bass kick every 0.25 s: every texel finite and within [0, 1] (full readback) and the health image clean; longer CPU runs on demand.
- **VIS-012-S3**: No frame runs more than 4 steps or 64 iterations at 10, 30, 60 and 120 fps.
- **VIS-012-S4**: Texture count, identities and allocated size constant over resizes, mode switches and reloads.
- **VIS-012-S5**: Goldens pass on the macOS host and the iOS Simulator; the other noise-field goldens are unchanged.
- **VIS-012-S6**: Flash tests: drawn pixels ≤ bound × gain ≤ 0.8; rapid reloads and bass bursts stay within the envelope's budget with Reduce flashing on and off.
- **VIS-012-S7**: One UI test under 30 s; new package host tests about 5 s in total.

## Assumptions

- The look and frame rate on D1 are `{device}` work; simulator results are not device evidence.
- Reaction Diffusion is not a scene layer kind.
- No network; the privacy manifest does not change.
