# Feature Specification: FX-019 Strobe safety envelope

**Feature Branch**: `feature/fx-019` (spec directory `022-fx-019-strobe-safety-envelope`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement FX-019 (Strobe safety envelope) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Constrain flash rate and
luminance delta across all effects." Acceptance, verbatim: "Synthetic alternating white/black
frames obey configured limiter." Dependencies: VIS-001 (integrated); extends spec 001's Reduce
flashing (FR-071, FR-072). Honor the repository constitution."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`FX-019-R1…`, success criteria `FX-019-S1…`, tasks `FX-019-T01…`. Requirements of feature 001 that
this row extends are cited by their own IDs and stay in force unchanged: FR-071 (photosensitivity
notice before any visualization), FR-072 (the Reduce flashing setting, on by default when the system
Reduce Motion setting is on) and FR-065 (what the app may store). VIS-001-R10 (native Reduce
flashing) and FX-001-R10 (Reduce flashing sees the glow) are kept and made stricter (FX-019-R9).

## Baseline: what exists today (audit of 2026-11-13, commit `e775e10`)

The row is an extension ("Extension (existing reduceFlashing)"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| projectM frames | `CFlashLimiter` (T104, T119): while Reduce flashing is on, a GPU post-pass slews the frame's mean luminance toward the scene's at most 0.3 per second, dimming brighter frames and **lifting darker frames with gray**. The mean is the luminance of the mean encoded color (an underestimate for high-contrast frames). Measured cost on D1: median 1.21 ms, max 1.55 ms (`docs/test-reports/performance.md`, T104). | No flash count, no red-flash handling, no local areas, nothing when the setting is off; a darker frame can be made brighter than the content. |
| Native visuals | `FlashSafetyLimiter` (VIS-001-R10, FX-001-R10): bars slew at most 4 per second; the whole-frame mean luminance (with the glow modeled) **rises** at most 0.25 per second; falls are bounded only by the bar slew. VIS-001 left "the full two-sided envelope" to this row. | No flash count, no red, no local areas, nothing when the setting is off. |
| Definition | Each limiter is a rate limit with its own constant (0.3 vs 0.25 per second); neither states what a flash is. | One definition of a flash and of the limits, with cited sources, shared by both renderers. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the safer option. ADR-0011 records the envelope's definition.

- Q: What is a flash, and where do the thresholds come from? → A: The W3C WCAG 2.x definition (SC 2.3.1 and its "general flash and red flash thresholds" definition): a *general flash* is a pair of opposing changes in relative luminance of 10 % or more of the maximum relative luminance (1.0), where the darker state is below 0.80; content passes when it has no more than three flashes in any one-second period. ITU-R BT.1702 and the Ofcom broadcast guidance use the same limits (pairs of opposing luminance changes of about 10 % of a 200 cd/m² display with the darker state below 160 cd/m², no more than three per second). Relative luminance is WCAG's: sRGB-decoded R, G, B weighted 0.2126, 0.7152, 0.0722. The app is stricter in two ways: it ignores the "darker state below 0.80" exemption (every opposing change of 0.10 or more counts) and it counts a lone unpaired change as a whole flash (flashes = transitions ÷ 2, rounded up) (FX-019-R1, R2).
- Q: How is a red flash handled? → A: WCAG's working definition of a transition involving saturated red: a change of (R − G − B) × 320 greater than 20, with negative values of R − G − B set to 0, R, G, B in 0…1 linear. The app tracks the area mean of max(R − G − B, 0) ("redness") as a second signal with threshold 20 / 320 = 0.0625 and the same counting and budgets as luminance. Stricter: WCAG's saturation condition R / (R + G + B) ≥ 0.8 is not applied, so any red-dominant change counts (FX-019-R3).
- Q: Is the whole-frame mean enough, given WCAG measures a flash over 25 % of any 10° visual field? → A: No. At a typical 30–40 cm viewing distance a 10° field is about 60–70 mm across, so 25 % of it is roughly 8 % of an iPhone screen and 3 % of an 11-inch iPad screen; a strobe on 8 % of the screen moves the whole-frame mean by only 8 % of its contrast. ITU-R BT.1702 uses one quarter of the screen. The envelope therefore watches 17 areas: the whole frame plus a 4 × 4 grid of tiles (each 6.25 % of the screen, smaller than ITU's quarter and about WCAG's field on a phone). One uniform gain satisfies every area. The residual limitation (a small flash straddling tile borders on a large iPad screen is diluted) is recorded in ADR-0011 for ACC-002/ACC-012 (FX-019-R4).
- Q: May the envelope brighten a frame (as the old projectM limiter lifted dark frames)? → A: No. The envelope only dims: every output frame is the input multiplied by one gain between 0 and 1, so no pixel is ever brighter than the content made it. Lifting a black frame with gray adds light the content never had and can itself start a transition. Falls are therefore bounded through the budget, not slowed: a rise that could be followed by a fall is allowed only if the pair still fits the budget (FX-019-R5, R6). Consequence: with Reduce flashing on, a sustained cut from bright to dark is now shown as a single cut (one transition, not a flash) instead of a gray fade; repetitions are what the envelope limits.
- Q: Does any envelope apply when Reduce flashing is off? → A: Yes, a looser always-on cap: the guideline's own limit (at most 6 transitions = 3 flashes in any 1 s window, general and red, in every area), with no rate limit, so normal pictures, single flashes and slow changes pass unchanged and only strobing faster than the guideline is clamped. Reason: FR-071 warns about flashing visuals but projectM presets are third-party content that can strobe at the frame rate; a user who never turned the setting on is still protected from the most extreme strobing. Cost: the projectM post-pass now runs on every frame (its T104 cost on D1 was 1.21 ms median); re-measuring on devices is a `{device}` task (FX-019-R7, S6).
- Q: What are the Reduce-flashing-on limits? → A: Stricter than the guideline: at most 4 transitions (2 flashes) in any 1 s window per area and signal, and the mean of every area may rise at most 0.25 per second (VIS-001's native constant, now also used for projectM, which was 0.3). With 0.25 per second a rise of 0.10 takes at least 0.4 s (FX-019-R8).
- Q: How is time measured? → A: By the frames: each frame advances the envelope's clock by its frame time clamped to 0…0.1 s, so a stall never opens the window early and nothing depends on the wall clock (FX-019-R10).
- Q: Does turning Reduce flashing on or off restart the envelope? → A: No. The envelope keeps its history across the toggle, size changes (rotation) and pause/resume of the native loop; only a new visual, or a projectM suspension that releases the GPU resources (PERF-011), starts from a clean history. Restarting on a toggle would let a burst of flashes through right after it (FX-019-R11).
- Q: What does the app observe or log about the envelope? → A: Nothing per frame: no logging, no counters written, no storage (Constitution VII, FR-065). Each renderer exposes the last applied gain for tests and diagnostics only; RendererLab keeps its T104 cost comparison (pass bypassed versus pass on) (FX-019-R13).
- Q: What if the projectM post-pass cannot be created on a device? → A: Frames are drawn directly, as spec 001 did, because no other GPU path can dim them; this is a failure state, not a mode. Tests on the simulator (ANGLE and the GLES fallback) assert that the pass is created and used with either setting, so a regression is caught before release (FX-019-R9).
- Q: How exact must the projectM path be compared with the shared definition, given 8-bit textures on the GPU? → A: The GPU stores the envelope's state with 16-bit precision (two 8-bit channels per value, as T104 already did) and uses a 0.005 margin below each threshold, so 8-bit rounding of the output (at most 1/255 in encoded value) cannot complete a transition the decision did not permit. GPU tests compare the GPU gain with the shared reference within 0.01 and measure the output pixels against the limits (FX-019-R6, S1).
- Q: Does this row add settings or stored values? → A: No. The Reduce flashing setting, its default (follows Reduce Motion), the notice (FR-071) and the stored keys stay exactly as spec 001 defines them. User-adjustable limits belong to ACC-012 (sensory safety profile), which builds on this envelope's configuration (FX-019-R12).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Strobing content is held within the limits (Priority: P1)

A user with Reduce flashing on watches a projectM preset or the native Circular Spectrum (with or
without the glow) while the music drives full-screen black/white or red/black strobing. The picture
keeps moving, but bright frames are dimmed so that no area of the screen produces more than two
flashes in any second, and brightness rises gently.

**Why this priority**: It is the row's observable behavior ("Constrain flash rate and luminance
delta across all effects") and its acceptance criterion.

**Independent Test**: Feed synthetic alternating white/black frames (60 Hz and 10 Hz), red/black
frames, 50 % gray steps and noise through the envelope and through each renderer's real pipeline;
measure the output's transitions per sliding 1 s window and its per-frame luminance deltas.

**Acceptance Scenarios**:

1. **Given** Reduce flashing is on, **When** full-screen frames alternate white/black at 60 Hz or 10 Hz, **Then** the output has at most 4 transitions (2 flashes) of 0.10 or more in any 1 s window and its mean luminance rises at most 0.25 per second of frame time.
2. **Given** Reduce flashing is on, **When** frames alternate red/black, **Then** both the luminance and the redness signals obey the same limits.
3. **Given** either setting, **When** any frame passes the envelope, **Then** no pixel is brighter than in the input frame.

---

### User Story 2 - Even with Reduce flashing off, extreme strobing is capped (Priority: P1)

A user who never turned Reduce flashing on plays strobing content. Ordinary pictures, single flashes
and fades look exactly as before; only strobing faster than three flashes per second is clamped.

**Why this priority**: Safety for every user (FR-071's warning alone does not protect).

**Independent Test**: With the setting off, a single white flash, a slow fade and steady content
pass unchanged; a 60 Hz white/black strobe yields at most 6 transitions in any 1 s window.

**Acceptance Scenarios**:

1. **Given** Reduce flashing is off, **When** a single white frame appears on black, **Then** it is shown unchanged.
2. **Given** Reduce flashing is off, **When** frames strobe white/black at 60 Hz, **Then** the output has at most 6 transitions (3 flashes) in any 1 s window.

---

### User Story 3 - Slow and steady content is untouched (Priority: P2)

Fades and steady pictures are never altered, and the envelope does not "pump" (oscillate in
brightness) when the input is steady.

**Independent Test**: A fade at 0.2 per second passes bit-for-bit through the pure envelope with
either setting; after a strobe stops, the output brightness recovers monotonically.

**Acceptance Scenarios**:

1. **Given** either setting, **When** the input fades slower than 0.25 per second, **Then** the output equals the input.
2. **Given** a strobe has just been clamped, **When** the input becomes constant, **Then** the output moves monotonically toward the input, with no oscillation.

### Edge Cases

- A stalled frame (frame time over 0.1 s, zero or negative) advances the clock by at most 0.1 s.
- A black or empty input (mean 0) needs no gain; the gain stays at 1.
- Non-finite measured values are treated as 0 (dark), never as permission to brighten.
- The first frame after a clean start is shown as it is (no history, no transition).
- Native visuals: the background is not scaled by the gain; if even gain 0 exceeds a ceiling (bright background), the gain is 0 (the darkest the envelope can make the frame).
- If the projectM post-pass cannot be created (missing GL entry point, shader failure), frames are drawn directly, as before; a renderer test checks that it is created on the supported paths.
- A local strobe in one tile dims the whole frame (one uniform gain), which is the conservative choice.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-019-R1** (definition): A *transition* in an area's signal is a reversal of at least the signal's threshold from the running extreme of the previous leg (hysteresis): a rise transition when the value reaches the running minimum plus the threshold, a fall transition when it reaches the running maximum minus the threshold. Legs alternate. The first transition after a clean start is measured from the first frame's value. The "darker state below 0.80" exemption is not applied.
- **FX-019-R2** (counting): A flash is a pair of opposing transitions; the envelope's budgets are stated in transitions per sliding window of 1 s (half-open: a transition counts while its age is below 1 s). Flashes in a window = transitions ÷ 2, rounded up.
- **FX-019-R3** (signals): Two signals per area: mean relative luminance (WCAG, sRGB-decoded, threshold 0.10) and mean redness max(R − G − B, 0) on linear R, G, B (threshold 0.0625 = 20 / 320).
- **FX-019-R4** (areas): The areas are the whole frame and a 4 × 4 grid of equal tiles. Every limit applies to every area and signal.
- **FX-019-R5** (only dims): The envelope applies one gain g with 0 ≤ g ≤ 1 to the frame (in linear light); no output pixel is brighter than its input.
- **FX-019-R6** (budget with reserved falls): A rise transition is permitted only while the window holds at most budget − 2 transitions; otherwise each area's ceiling is its running minimum plus the threshold minus a margin of 0.005. Falls are always permitted (they were reserved). Result: at most `budget` transitions in any window.
- **FX-019-R7** (always on): With Reduce flashing off the budget is 6 transitions (3 flashes, the guideline's limit) per window and there is no rise-rate limit.
- **FX-019-R8** (Reduce flashing on): The budget is 4 transitions (2 flashes) per window, and each area's signal may rise at most 0.25 per second of clamped frame time above its previous output.
- **FX-019-R9** (both renderers): The same definition, constants and decision rule apply to projectM frames (ANGLE path and the GLES fallback) and to native visuals after every effect (the glow included, FX-001-R10). VIS-001-R10's bar slew stays for native visuals with Reduce flashing on.
- **FX-019-R10** (time): The envelope's clock is the sum of frame times clamped to 0…0.1 s; no wall clock.
- **FX-019-R11** (state): Toggling Reduce flashing, resizing and pausing keep the history (the native visual's `reset()` on a loop restart restarts only the bar slew); a new visual, or a projectM suspension that releases the GPU state (PERF-011), starts clean.
- **FX-019-R12** (no new settings): Reduce flashing, its default and the notice stay as FR-071 and FR-072 define them; nothing new is stored (FR-065).
- **FX-019-R13** (real-time safety): No allocation, lock or I/O per frame in the envelope; deterministic results for identical input.
- **FX-019-R14** (configuration for later rows): The limits are one value type (thresholds, window, budget, rise rate), so ACC-002 (reduced-flash preset policy) and ACC-012 (sensory safety profile) can apply stricter values, and PERF-003 (adaptive quality) must never remove the pass; this row implements neither.

### Key Entities

- **Envelope configuration**: window, luminance and redness thresholds, transition budget, optional rise rate, gate margin, maximum frame time. Two fixed instances: Reduce flashing on and the always-on cap.
- **Envelope state** (per area and signal): last shown value, running extremes, leg direction, ages of the recent transitions (at most 6).
- **Flash analysis**: an independent offline measurement of a sequence (transitions per window, worst count, largest per-frame rise and fall) used by tests and, later, ACC-002.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-019-S1**: With Reduce flashing on, synthetic white/black alternation at 60 Hz and 10 Hz yields at most 4 transitions in any 1 s window and rises of at most 0.25 per second of frame time, in the pure envelope and measured on rendered pixels of both pipelines (tolerance 0.01 for 8-bit rounding).
- **FX-019-S2**: With Reduce flashing off, the same 60 Hz strobe yields at most 6 transitions in any 1 s window; a single flash and a 0.2-per-second fade pass unchanged.
- **FX-019-S3**: Red/black alternation, 50 % gray steps and seeded noise obey the same limits on both signals.
- **FX-019-S4**: No output frame is brighter than its input (per pixel, within 1/255 rounding).
- **FX-019-S5**: Identical input gives identical output on repeated runs; a constant input after a strobe gives a monotone output (no pumping).
- **FX-019-S6** `{device}`: The projectM post-pass costs at most 2 ms per frame on D1 (T104 method), now with the setting off as well.
- **FX-019-S7**: Existing VIS-001 and FX-001 Reduce-flashing tests still pass, changed only where this row is intentionally stricter.

## Assumptions

- Synthetic acceptance uses solid frames for the projectM pipeline and the native visual's own content (bars alternating full/empty, white and red palettes) for native visuals; simulator and Mac GPU runs are test evidence for the logic, not device evidence (Constitution X).
- The engine's framebuffer holds sRGB-encoded 8-bit color, so luminance is computed with the sRGB transfer function; native visuals already work in linear light.
- Area means are estimated from about 4,000 bilinear samples per frame on the projectM path (the same sample budget as T104's mean) and computed exactly from geometry on the native path (bar light attributed to the tiles it covers; glow light attributed to the bar's own tiles, an approximation recorded in ADR-0011, while the whole-frame area stays an exact upper bound).
