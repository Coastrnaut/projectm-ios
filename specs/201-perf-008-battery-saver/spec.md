# Feature Specification: PERF-008 Battery saver profile

**Feature Branch**: `feature/perf-008` (spec directory `201-perf-008-battery-saver`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PERF-008 (Battery saver profile) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Offer explicit low-power settings beyond automatic thermal governor." Acceptance,
verbatim: "Profile changes effect budgets without changing audio source state." P1, size M, extension of the
existing QualityGovernor."

Identifiers carry the roadmap ID: requirements `PERF-008-R1…`, success criteria `PERF-008-S1…`, tasks
`PERF-008-T01…`. Other features are cited by their own IDs: FR-049 (QualityGovernor, T100), PERF-003 (adaptive
effect quality), PERF-005 (prewarm scheduler), SC-104 (preset warm-up), REC-006 (recording render limit), FR-048
(performance overlay), FILE-005/FILE-011 (settings backup and erase).

## Baseline: what exists today (audit of 2026-11-14, commit `f089007a`)

| Area | Today |
|---|---|
| Governor (FR-049, T100) | `QualityGovernor` (Packages/Rendering) maps thermal state and Low Power Mode to a frame-rate cap (60 or 30, floor 30) and a render scale (1.0, or 0.75 at critical). `QualityGovernor.current()` reads `ProcessInfo`; it has no user input. |
| Consumers | ANGLE (projectM) and GLES renderers, the native spectrum, Camera, Photo, Video and Text hosts read `current()` at start and again on the thermal and power-state notifications; PERF-002's frame deadline reads it; REC-006's recording render limit reads `settings(thermal:lowPower:)`. |
| PERF-003 | The native host defers the serious-state cap to its effect ladder (`adaptiveEffects`). |
| Background work | PERF-005 `MediaPrewarmCoordinator`: thermal serious/critical pauses media prewarm, Low Power keeps only the next cue. SC-104 preset warm-up (`RendererPresetLoader.prewarm`, 2.5 s after a switch) renders upcoming presets on a background context. |
| Settings | Settings → Performance has only the "Performance overlay" toggle. No power choice exists. |
| Audio | `CaptureManager` owns the source, its state and configuration; nothing in the governor touches it (FR-049). |

The gap: the user cannot ask for lower power use; the app only reacts to the system.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose battery saver (Priority: P1)

A performer running a long set on battery opens Settings → Performance and picks "Battery saver". The visual
keeps running at a lower frame rate and resolution and background warm-ups stop, while the audio source keeps
playing exactly as before.

**Why this priority**: it is the roadmap behaviour and its acceptance.

**Independent Test**: switch the profile while a source runs; the governor's budgets change, the capture state
and configuration do not.

**Acceptance Scenarios**:

1. **Given** Standard and nominal thermal state, **When** the user picks Battery saver, **Then** every visual is
   capped at 30 fps and 0.75 render scale, the preset warm-up is skipped and media prewarm keeps only the next cue.
2. **Given** a running audio source, **When** the profile changes in either direction, **Then** the source, its
   state, its configuration and its start count are unchanged.
3. **Given** Battery saver and a critical thermal state, **When** the governor evaluates, **Then** the result is
   never higher than either the thermal result or the profile cap (30 fps, 0.75), and never below the 30 fps floor.

### User Story 2 - Follow Low Power Mode (Priority: P2)

A user who wants the saving only when the system is in Low Power Mode picks "Follow Low Power Mode": the battery
saver budgets apply while Low Power Mode is on and Standard applies otherwise.

**Independent Test**: governor results for the profile with Low Power on and off.

**Acceptance Scenarios**:

1. **Given** Follow Low Power Mode and Low Power off, **Then** the budgets equal Standard's.
2. **Given** Follow Low Power Mode and Low Power on, **Then** the budgets equal Battery saver's.

### Edge Cases

- Unknown or missing stored value: Standard (today's behaviour, nothing stored until changed).
- A recording in progress: the profile's cap is shown as the recording's render limit (REC-006), with its own reason.
- Profile changes while the app is in the background: applied on the next notification; nothing restarts.
- Thermal critical already lowers scale to 0.75: the profile does not compound it (no 0.56).

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-008-R1**: Settings → Performance offers three power profiles: Standard (default), Follow Low Power Mode,
  Battery saver; exactly one is selected.
- **PERF-008-R2**: Each profile defines a budget: a frame-rate cap, a render-scale cap, and whether background
  warm-up work (SC-104 preset warm-up, PERF-005 media prewarm beyond the next cue) is allowed. Standard: 60 fps,
  1.0, allowed. Battery saver: 30 fps, 0.75, not allowed.
- **PERF-008-R3**: The governor's result is the lower of its thermal/Low Power result and the active budget, per
  value; it never exceeds the budget and never falls below the 30 fps floor.
- **PERF-008-R4**: A profile change reaches every visual's frame loop and render scale without restarting it.
- **PERF-008-R5**: A profile change does not start, stop, switch or reconfigure the audio source; the capture
  state and configuration are identical before and after.
- **PERF-008-R6**: The choice persists across launches as a preference, is included in the settings backup
  (FILE-005), erased with Settings (FILE-011) and reset by the UI-test reset.
- **PERF-008-R7**: Each profile change is marked with a signpost event (no user content) so a device trace can
  line up frame time and power with the change.
- **PERF-008-R8**: The recording render limit (REC-006) reflects the profile's cap with the reason "Battery saver".

### Key Entities

- **Power profile**: standard, followLowPowerMode, batterySaver.
- **Power budget**: frame-rate cap, render-scale cap, background warm-up allowed.

## Success Criteria *(mandatory)*

- **PERF-008-S1**: Switching between Standard and Battery saver changes the frame-rate cap (60 → 30) and render
  scale (1.0 → 0.75) in 100% of the tested thermal/Low Power combinations where the system did not already lower them.
- **PERF-008-S2**: In 100% of profile switches the audio source state and configuration are unchanged.
- **PERF-008-S3**: On D1, a 5-minute session under Battery saver uses measurably less energy per minute than
  Standard with the same preset and source `{device}`.

## Assumptions

- Standard keeps today's behaviour exactly (FR-049 table, PERF-003 deferral).
- The profile limits only the visual's budgets; audio analysis, capture and recording encoding settings are unchanged.
- Simulator results are not performance evidence; S3 is measured on D1 last.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Which profiles? → A: Standard (default, unchanged behaviour), Follow Low Power Mode, Battery saver. No "performance" profile above Standard: the roadmap asks for lower power only.
- Q: What does Battery saver cap? → A: 30 fps (the FR-049 floor), render scale 0.75 (the critical-state value, already proven on D1-D3), and background warm-ups (SC-104 preset warm-up skipped; PERF-005 media prewarm keeps only the next cue, its Low Power rule). Audio analysis is not touched.
- Q: How does it combine with the thermal governor? → A: Per-value minimum; the governor can lower further but never above the profile cap; caps do not compound.
