# Feature Specification: MOD-006 Threshold Trigger

**Feature Branch**: `feature/mod-006` (spec directory `148-mod-006-threshold-trigger`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-006 (Threshold trigger) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Turn continuous input into debounced discrete trigger events." Acceptance,
verbatim: "Noise around threshold produces no trigger storm." Priority P1, effort S, depends on MOD-002
(integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-006-R1…`, success criteria
`MOD-006-S1…`, research decisions `MOD-006-D1…`, tasks `MOD-006-T01…`. Other features are cited by their
own IDs: MOD-002 (audio feature bindings and sources), MOD-005 (envelope, injected clock), ANL-004 /
ANL-007 / ANL-008 (onset, kick and mid-transient detectors, which already have their own refractory
periods), MIDI-006 (note trigger actions), SHOW-001 (cues), OUT-010 (blackout), SCN-001 / SCN-012
(scene document and its issue report), QA-004 (scene migration matrix meta-test).

## Baseline: what exists today (audit of 2026-11-14, commit `4bad23aa`)

| Question | Today |
|---|---|
| Continuous inputs | MOD-002's `AudioFeatureSource` reads eight normalized (0…1) features per frame: a band, the band mean, onset, beat confidence, kick, centroid, loudness, mid transient. Non-finite readings are 0. |
| Discrete events from audio | Only inside the analysis detectors (ANL-004 onsets, ANL-007 kicks, ANL-008 mid transients), each with its own refractory period, and not configurable by a scene. Nothing turns an arbitrary feature into an event. |
| Trigger actions | MIDI-006 maps notes to `cue.next`, `cue.previous`, `blackout` (toggle) and `blackout` while held, performed by the app's `MIDINoteActionPerformer` (SHOW-001 step, OUT-010 blackout). |
| Clock | Bindings use the frame's display time passed in (`timeNanoseconds`); no wall clock. |
| Scenes | Bindings, modulation, groups and effects are stored; there is no trigger field. |
| UI | No binding editor (MOD-004 and MOD-005 had none either). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Where are triggers stored: in scenes or in app settings? → A: In scenes, as an optional top-level `triggers` list written only when the scene has triggers (format version 1 unchanged, so QA-004's matrix gains no row). A trigger is then opt-in per scene and never on by default; no UserDefaults key is added. Rejected: a global setting (every kick would step the show in every scene, and a new key would need the backup and erase lists). Triggers follow MOD-002's binding path in the app: they become live when the native visual is created from the current scene (MOD-006-R9, R11).
- Q: Which actions can a threshold trigger drive? → A: The MIDI-006 trigger-mode actions only: `cue.next`, `cue.previous`, `blackout` (toggle), stored by the same identifiers and performed by the same performer. "Black out while held" is not offered: a continuous level held above a threshold would black out for as long as the music is loud, which is a safety and usability risk with no acceptance need (MOD-006-R8).
- Q: What happens to a crossing that arrives inside the minimum interval? → A: It is consumed: it disarms the trigger without firing and is never delivered late; the input must fall below `low` and rise above `high` again after the interval. Fewer events is the conservative failure mode for cue stepping (MOD-006-R2).
- Q: How is a non-finite input treated? → A: As no information: it neither fires nor re-arms, and it restarts a pending hold. Rejected: reading it as 0 (MOD-002's binding rule), which would re-arm the trigger and let alternating NaN and loud frames fire on every interval (MOD-006-R5). The MOD-002 source reading already turns missing features into 0, so in the app this applies to direct callers of the pure step.
- Q: Is a trigger editor or any other UI added? → A: No. There is no binding editor (MOD-004 and MOD-005 decided the same); the model, scene persistence, scene issue reporting and the app's per-frame evaluation are complete, and the row's app verification is an app unit test on the simulator. A newly created trigger starts armed (the first loud frame fires once); limits are 8 triggers per scene, levels in 0…1, interval and hold in 0…60 s, defaults interval 100 ms and hold 0 (MOD-006-R7, R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A noisy input near the threshold fires once, not a storm (Priority: P1)

A scene author makes the show react to the music: when a feature (for example the kick) goes over a
level, the show steps to the next cue. Real audio hovers around any level, so the trigger must fire once
when the level is crossed and stay quiet while the input wobbles near it.

**Why this priority**: This is the roadmap acceptance: "Noise around threshold produces no trigger storm."

**Independent Test**: Feed 10 s of seeded random noise at 60 frames per second around the threshold, with
an amplitude smaller than the gap between the fire level and the re-arm level, and count the triggers.

**Acceptance Scenarios**:

1. **Given** a trigger with fire level `high` and re-arm level `low`, **When** the input is noise of
   amplitude below `high − low` centred on `high` or on `low`, or below half of it centred on their midpoint, for 10 s at 60 fps, **Then**
   at most one trigger fires.
2. **Given** a clean pulse train (each pulse rises above `high`, then falls below `low`) with pulses
   farther apart than the minimum interval, **When** it plays, **Then** exactly one trigger fires per
   pulse, on the frame the pulse first exceeds `high`.
3. **Given** pulses closer together than the minimum interval, **When** they play, **Then** no two
   triggers are closer than the minimum interval.

---

### User Story 2 - Timing is the same at any frame rate and robust to bad input (Priority: P1)

The trigger's timing (minimum interval, hold time) depends on elapsed time, not on frame count, so
60 fps, 120 fps and an uneven frame rate behave alike. Missing or non-numeric input never fires a
trigger, and two runs with the same input give the same triggers.

**Why this priority**: A trigger that fires twice as often at 120 fps, or on a corrupt value, would
skip cues unpredictably.

**Independent Test**: The same pulse train at 60 fps, 120 fps and seeded jitter gives the same trigger
count; NaN and infinite inputs, repeated and backwards frame times; two identical runs.

**Acceptance Scenarios**:

1. **Given** a minimum interval of 100 ms, **When** pulses arrive every 80 ms at 60 fps, 120 fps or with
   jitter, **Then** consecutive triggers are at least 100 ms apart.
2. **Given** a hold time, **When** the input stays above `high` for less than the hold time, **Then**
   nothing fires; **When** it stays above for the hold time, **Then** one trigger fires.
3. **Given** a non-finite input, **When** the trigger is evaluated, **Then** it neither fires nor re-arms.

---

### User Story 3 - A scene keeps its triggers and they drive the show (Priority: P2)

A scene stores its triggers (source, action, levels, interval, hold). Opening the scene makes them live;
in the app a kick-driven trigger steps to the next cue once per kick. A scene with a trigger this
version cannot use still opens, reports where the problem is, and keeps the trigger for re-save.

**Why this priority**: Without persistence a trigger exists only in code.

**Independent Test**: Scene round trip; a scene with invalid and unknown triggers; an app unit test with
a kick-shaped input driving the cue action.

**Acceptance Scenarios**:

1. **Given** a scene with triggers, **When** it is saved and reopened, **Then** the triggers are equal and
   behave identically.
2. **Given** a scene without triggers, **When** it is saved, **Then** the stored text is unchanged
   (no new field written).
3. **Given** a trigger with `low ≥ high`, an unknown action or an unknown source, **When** the scene
   opens, **Then** the scene opens, the trigger is not live, a warning names its path, and the trigger
   is written back unchanged.
4. **Given** the app with a kick trigger on Next cue, **When** four kicks play, **Then** Next cue is
   performed four times.

### Edge Cases

- Input exactly equal to `high` does not fire; exactly equal to `low` does not re-arm.
- The first frame already above `high`: a newly created trigger is armed, so it fires (once).
- A crossing during the minimum interval is consumed: it does not fire later; the input must fall below
  `low` and rise again after the interval.
- The hold timer restarts whenever the input drops to `high` or below, or is not a number.
- Frame time that repeats or goes backwards counts as no elapsed time.
- More triggers in a scene than the limit: the extra ones are reported and kept, not live.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-006-R1**: A trigger MUST fire when its input rises above its fire level `high` while armed, then
  disarm; it MUST re-arm only after the input falls below its re-arm level `low` (hysteresis), with
  `low < high`.
- **MOD-006-R2**: Two fires of one trigger MUST be at least its minimum interval apart (default 100 ms);
  a crossing within the interval is consumed without firing.
- **MOD-006-R3**: An optional hold time (default 0) MUST require the input to stay above `high`
  continuously for that long before firing.
- **MOD-006-R4**: Timing MUST come only from the frame times passed in (injected clock), never from the
  frame count or a wall clock; non-increasing time counts as no elapsed time.
- **MOD-006-R5**: A non-finite input MUST neither fire nor re-arm, and MUST restart a pending hold.
- **MOD-006-R6**: Results MUST be deterministic: identical inputs give identical fires.
- **MOD-006-R7**: Valid settings: `low` and `high` finite within 0…1 with `low < high`; interval and hold
  finite within 0…60 s. Invalid settings MUST be refused when a trigger is created and when a scene is
  opened.
- **MOD-006-R8**: A trigger's source MUST be any MOD-002 audio feature; its action MUST be one of the
  MIDI-006 trigger actions: Next cue, Previous cue, Black out (toggle).
- **MOD-006-R9**: A scene MUST store its triggers in a new optional field, written only when the scene has
  triggers, with no format version change; unknown fields of a trigger are kept verbatim.
- **MOD-006-R10**: A stored trigger that is invalid, uses an unknown source or action, or exceeds the
  limit (8 per scene) MUST be reported with a warning at its path, not applied, and kept for re-save.
- **MOD-006-R11**: The app MUST evaluate a scene's live triggers once per frame with the frame's audio
  features and perform each fire through the same action path as MIDI-006 note triggers.
- **MOD-006-R12**: The trigger MUST be available as a pure, allocation-free step that builds on every CI
  host (Linux included).

### Key Entities

- **Threshold trigger**: settings (fire level, re-arm level, minimum interval, hold time) and state
  (armed, time above the fire level, time of the last fire).
- **Trigger binding**: an audio feature source, a trigger action and the trigger settings.
- **Stored trigger**: one entry of a scene's trigger list, kept as written.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-006-S1**: 10 s of seeded noise at 60 fps with amplitude below the hysteresis width centred on the
  fire level or the re-arm level, and below half the width centred on their midpoint, gives at most one trigger in every case.
- **MOD-006-S2**: A clean pulse train gives exactly one trigger per pulse; with pulses closer than the
  minimum interval, no two triggers are closer than the interval, at 60 fps, 120 fps and with jitter.
- **MOD-006-S3**: No tested non-finite input or frame-time anomaly produces a trigger; two runs are
  identical.
- **MOD-006-S4**: A scene round trip keeps the triggers exactly; a scene without triggers encodes as
  before; invalid and unknown triggers are reported at their paths and kept.
- **MOD-006-S5**: In the app, a kick-driven trigger performs Next cue exactly once per kick.
- **MOD-006-S6**: The ParameterGraph and SceneFormat suites keep passing on macOS and Linux, each under
  one minute.

## Assumptions

- No trigger editor is added (no binding editor exists; MOD-004 and MOD-005 decided the same). Triggers
  are made in code and scenes.
- The detectors' own refractory periods (ANL-004/007/008) are unchanged; this trigger is generic.
- No settings key is added; triggers live only in scenes.
