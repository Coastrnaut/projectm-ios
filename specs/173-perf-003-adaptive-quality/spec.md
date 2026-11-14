# Feature Specification: PERF-003 Adaptive effect quality

**Feature Branch**: `feature/perf-003` (spec directory `173-perf-003-adaptive-quality`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-003 (Adaptive effect quality) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Reduce costly effect iterations before dropping output frames." Acceptance,
verbatim: "Simulated thermal stress lowers effect quality and preserves safety limiter." P1, size L, extends the
existing QualityGovernor, depends on FX-001."

Identifiers carry the roadmap ID: requirements `PERF-003-R1…`, success criteria `PERF-003-S1…`, tasks
`PERF-003-T01…`. Other features are cited by their own IDs: FR-049 (quality governor), FX-001 (glow/bloom),
FX-019 (strobe safety envelope), ACC-012 (sensory safety clamp), FR-072 (Reduce flashing), PERF-001 (stage
timings), PERF-002 (frame budget meter), FR-048 (performance overlay), FR-021 (diagnostics export).

## Baseline: what exists today (audit of 2026-11-14, commit `5aaeebe5`)

| Area | Today |
|---|---|
| Quality governor (FR-049, T100) | `QualityGovernor.settings(thermal:lowPower:)`: 60 fps; 30 fps under Low Power or at the serious or critical thermal state; render scale 0.75 at critical. Every visual's display link uses it. Its inputs are only the thermal state and Low Power. It never touches effects. |
| Glow (FX-001) | `BloomEffect`: a threshold + downsample (D = 2, 4 or 8) compute pass, a horizontal and a vertical Gaussian blur pass of R ≤ 16 taps per side in reduced texels, and a composite render pass. Runs in the native spectrum host (circular, linear, oscilloscope, Lissajous) and in the compositor's spectrum layers. The plan (D, R) depends only on the radius and output size. The costliest effect on the native visuals: three compute dispatches over the reduced image plus a full-screen pass every frame. |
| Trails (FX-009), effect chain (FX-020), layer cache (CMP-013), Lissajous persistence (VIS-004) | Single-pass feedback blends and cached layer pictures in the compositor; the Lissajous persistence is one decay blend inside its generator. Each is one pass, not an iterated one. |
| Flash safety (FX-019, FR-072, ACC-012) | `FlashSafetyLimiter` with a `FlashEnvelope` limits every native frame; the glow's luminance model (`BloomLuminanceModel`, an upper bound of the composited frame) is the limiter's downstream transfer. ACC-012's `SafetyClamp` caps the glow intensity before render. |
| Budget (PERF-001, PERF-002) | `FrameBudgetMeter` judges PERF-001's p95 stage times against the frame deadline once a second while the performance overlay is on, and flags over-budget passes. Purely observational. |
| Overlay and export | The overlay shows fps, stage lines and PERF-002's budget lines; the diagnostics `frameTimings` section carries an optional `budget`. Nothing names an effect quality. |

The gap: under thermal pressure the only lever is the frame-rate cap, which drops output frames even when a
cheaper glow would have kept the frame inside its budget.

**Owner ruling context.** CLAUDE.md records "no quality tiers ... for Gate 3" (2026-11-09). That ruling was
about what Gate 3 had to measure, not a ban on adaptation. This roadmap row asks for adaptive quality, so it is
implemented conservatively and automatically: there are no user-facing tiers, no new setting, and the nominal
path is unchanged bit for bit.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Which effects does the ladder reduce? → A: Only the FX-001 glow, the one iterated, multi-pass effect (prefilter, two blur passes, composite). Trails, the effect chain's single passes, layer caching and the Lissajous persistence are single blends whose removal would visibly change the picture for little saving; they stay as they are (recorded in research).
- Q: Which levels exist? → A: Three, ordered: Full (today's glow), Reduced (half the blur taps, and a coarser glow image where that keeps the halo no wider than at Full), Minimal (the glow pass is skipped). There are no other levels and no user-facing names beyond the overlay's diagnostic line.
- Q: Is there a user setting ("Adaptive quality")? → A: No. Adaptation is automatic, with no new stored key and no Settings row; a DEBUG launch argument injects the inputs for tests.
- Q: Which inputs move the level? → A: The thermal state, Low Power Mode and PERF-002's budget verdict (any flagged pass) while it is available.
- Q: How does adaptation relate to the frame-rate cap? → A: Effects step down first. While a glow is on (the ladder has something to reduce), the serious thermal state lowers the glow instead of capping the frame rate; the 30 fps cap and the 0.75 render scale engage at critical, as today. Low Power keeps its 30 fps cap (the user's own choice). With no glow on, the governor behaves exactly as today. FR-049 says the visualization MAY lower its frame rate, so this is within FR-049 and needs no ADR.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: When the budget verdict becomes unavailable (overlay turned off) while budget steps are applied, does the level jump back up at once? → A: No. The over-budget timer is cleared, but the level returns only through the normal hysteresis (one step per 10 s of good conditions), so turning the overlay off never makes the glow jump.
- Q: What state does the ladder start in when a visual's frame loop starts or the shown visual changes? → A: Each native host owns one ladder. Starting the loop sets the applied level straight to the thermal and Low Power floor with full glow weight and no fade (the picture starts fresh, as the Reduce-flashing limiter does), and clears the timers.
- Q: Does the overlay show the line at Full too? → A: Yes. While the overlay is on and a native visual is shown it always shows `effect quality full`; at Reduced or Minimal it adds the reason in parentheses, e.g. `effect quality reduced (thermal)`. Other visuals (projectM, camera, photo, video, text) show no line, since they have no adaptable effect.
- Q: Does a recording (REC-003) or a frame capture (REC-001) hold the level? → A: No. They copy the frame as shown, so they record the adapted glow; holding Full during a recording would defeat the thermal protection.
- Q: Which reason is shown when several inputs apply? → A: The strongest: `thermal` when the thermal floor alone gives the current level, else `low power` when Low Power does, else `budget`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep the frame rate under thermal stress by simplifying the glow (Priority: P1)

A performer runs the circular spectrum with the glow on for a long set. When the device warms up (serious
thermal state) or the frame budget is exceeded, the glow becomes cheaper (fewer blur taps, coarser glow
image) instead of the frame rate halving; only at the critical thermal state does the glow switch off and the
frame rate cap engage. When the device cools, the glow returns step by step.

**Why this priority**: The roadmap row.

**Independent Test**: Inject thermal states nominal → serious → critical into the ladder with an injected
clock: the level goes Full → Reduced → Minimal, and the governor's 30 fps cap is reported only at critical.

**Acceptance Scenarios**:

1. **Given** the glow on and the nominal state, **When** the state becomes serious, **Then** the effect level becomes Reduced and the frame-rate cap stays at 60 fps.
2. **Given** the serious state, **When** it becomes critical, **Then** the level becomes Minimal and only now the 30 fps cap and the 0.75 render scale apply.
3. **Given** the nominal state and a budget verdict that stays over budget for 3 s, **When** the ladder is stepped, **Then** the level drops one step; another 3 s over budget drops it again (never below Minimal).
4. **Given** Reduced or Minimal, **When** the inputs are back to nominal and under budget, **Then** the level rises one step only after 10 s of good conditions, and one step at a time.
5. **Given** the glow at Reduced, **When** the glow pass is encoded, **Then** its blur taps and glow-image size are smaller than at Full; at Minimal no glow pass is encoded.

### User Story 2 - Safety never degrades with quality (Priority: P1)

A viewer with Reduce flashing or a sensory safety profile on is exactly as protected at every effect level:
the strobe safety envelope, the ACC-012 clamp and Reduce flashing are never bypassed or relaxed, and a level
change itself never makes a flash.

**Independent Test**: Feed a strobe fixture (bands alternating 0/1 every frame) through the limiter with the
glow at each level and across level changes; the composited luminance obeys the same bound with the same
envelope configuration as at Full.

**Acceptance Scenarios**:

1. **Given** each level, **When** the strobe fixture is limited, **Then** the luminance rise never exceeds the same bound as at Full, and the envelope configuration is identical.
2. **Given** a level change, **When** it happens, **Then** the glow fades out over 0.4 s, the new level is applied while the glow is at zero, and it fades back in over 0.4 s; the glow is never brighter than the ACC-012-clamped value during the change.

### User Story 3 - See and export the level (Priority: P2)

A tester with the performance overlay on sees "effect quality reduced (thermal)", and the
diagnostics export carries the level.

**Acceptance Scenarios**:

1. **Given** the overlay on, **When** the level is Reduced because of the thermal state, **Then** the overlay's lines include `effect quality reduced (thermal)`.
2. **Given** a diagnostics export of frame timings, **When** a level is known, **Then** the export carries it; otherwise the export is unchanged and schema-valid.

### Edge Cases

- No glow on: the ladder still tracks a level for the overlay, but nothing is reduced and the governor is exactly today's.
- Budget unavailable (overlay off): the ladder uses only thermal state and Low Power; the over-budget timer is cleared and budget-driven steps are undone only through the normal 10 s hysteresis.
- The loop starts (or the visual changes): the level is set to the floor at once, with no fade and cleared timers.
- Inputs flap faster than the hold times: a step down needs 3 s of sustained over-budget (thermal steps are immediate); a step up needs 10 s of good conditions, so flapping cannot oscillate faster than one step per 10 s upward.
- A level change while a fade is running: the fade reverses from its current weight; the glow never jumps.
- The thermal state worsens directly from nominal to critical: the level goes straight to Minimal (with one fade).
- Non-finite or backwards clock values: ignored (no step).

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-003-R1**: The effect quality MUST be one of three ordered levels: Full, Reduced, Minimal.
- **PERF-003-R2**: The thermal floor MUST be: nominal or fair → Full; serious → Reduced; critical → Minimal. Low Power Mode MUST give at most Reduced.
- **PERF-003-R3**: A budget verdict that stays over budget for 3 s MUST lower the level one step (to at most Minimal); each further 3 s over budget lowers one more step. An unavailable verdict MUST NOT move the level and clears the over-budget timer.
- **PERF-003-R4**: The level MUST rise by at most one step after 10 s in which the thermal floor allows the higher level and the budget is not over (hysteresis). Thermal step-downs MUST be immediate.
- **PERF-003-R5**: The ladder MUST be deterministic: its only inputs are the thermal state, Low Power, the budget verdict and an injected monotonic time; it runs on Linux.
- **PERF-003-R6**: At Reduced, the glow MUST use at most half the blur taps per side of Full and, where it keeps the halo extent no larger than at Full, a coarser glow image; the halo extent MUST never exceed Full's. At Minimal the glow pass MUST be skipped. At Full the glow MUST be bit-identical to today.
- **PERF-003-R7**: While a glow is on, the governor MUST NOT cap the frame rate at the serious state (the ladder handles it); at critical, and under Low Power, it caps as today. With no glow on it MUST behave exactly as FR-049 today.
- **PERF-003-R8**: The flash safety envelope (FX-019), Reduce flashing (FR-072) and the ACC-012 clamp MUST be applied identically at every level; the ladder may only lower the glow's intensity weight, after the ACC-012 clamp, and the luminance model the limiter sees MUST follow the glow actually rendered.
- **PERF-003-R9**: Each level change MUST fade the glow out over 0.4 s, switch the level at zero glow, and fade back in over 0.4 s; a change during a fade reverses from the current weight.
- **PERF-003-R10**: While a native visual is shown, the performance overlay MUST show a line `effect quality <level>`, with the reason in parentheses (`thermal`, `low power` or `budget`, the strongest that applies) when not Full; the diagnostics frame timings MUST gain an optional effect quality (level and reason); exports without it are unchanged.
- **PERF-003-R11**: In DEBUG builds a launch argument `-uitestThermalState <nominal|fair|serious|critical>` MUST override the thermal input so the ladder can be tested in the simulator.
- **PERF-003-R12**: The frame path MUST gain no allocation: stepping the ladder is arithmetic on preallocated state, and plan changes happen only on a level change.

### Key Entities

- **Effect quality level**: Full, Reduced, Minimal.
- **Ladder inputs**: thermal state, Low Power flag, budget verdict (over, within, unavailable), time.
- **Ladder state**: applied level, target level, fade weight and phase, over-budget and good-conditions timers, budget steps.
- **Reduced glow plan**: downsample and blur radius derived from the Full plan, with a halo no wider than Full's.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-003-S1**: Under injected nominal → serious → critical, the level steps Full → Reduced → Minimal and the frame-rate cap is 60, 60, 30 fps respectively (glow on).
- **PERF-003-S2**: At Reduced the glow's blur taps per side are at most half of Full's and its work (threadgroups × taps) is lower; at Minimal zero glow passes are encoded.
- **PERF-003-S3**: With the strobe fixture, the luminance rise stays within the same bound (≤ 100% of it) at every level and across level changes, with the same envelope configuration.
- **PERF-003-S4**: Recovery from Minimal to Full takes two steps, each after at least 10 s of good conditions.
- **PERF-003-S5**: At nominal with the glow on, the rendered glow and the frame-rate settings are identical to today's.
- **PERF-003-S6**: The overlay and the export name the level; tests run within the owner's short-test budgets.

## Assumptions

- The ladder runs inside the native spectrum host, where the glow runs on screen; the compositor's spectrum layers keep Full (their thermal adaptation is left to a later row).
- The budget verdict exists only while the performance overlay is on (PERF-002 runs then); otherwise thermal state and Low Power alone drive the ladder.
- Device evidence (D1 under real thermal load) is a `{device}` task; simulator results are not performance evidence.
