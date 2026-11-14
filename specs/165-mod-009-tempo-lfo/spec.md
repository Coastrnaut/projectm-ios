# Feature Specification: MOD-009 Tempo-Synced LFO

**Feature Branch**: `feature/mod-009` (spec directory `165-mod-009-tempo-lfo`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-009 (Tempo-synced LFO) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Quantize oscillator cycles to detected or manual tempo." Acceptance,
verbatim: "At 120 BPM a quarter-note cycle lasts 0.5 seconds." Priority P1, effort M, depends on ANL-005
and MOD-007 (both integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-009-R1…`, success criteria
`MOD-009-S1…`, research decisions `MOD-009-D1…`, tasks `MOD-009-T01…`. Other features are cited by their
own IDs: MOD-007 (sine and triangle oscillators, `audio.lfo.<index>` binding source, scene `lfos` list),
ANL-005 (adaptive beat tracker: tempo estimate with a confidence), ANL-006 (tempo confidence states),
SHOW-011 (tap tempo and the one tempo snapshot every consumer reads), ACC-012 / FR-072 (Reduce flashing),
SCN-001 / SCN-012 (scene document and its issue report), QA-004 (scene migration matrix meta-test).

## Baseline: what exists today (audit of 2026-11-14, commit `0c57cf7c`)

| Question | Today |
|---|---|
| Oscillators | MOD-007: sine and triangle, rate 0.01…20 Hz, phase, amplitude, centre; the value is a pure function of the integer elapsed nanoseconds since the bank's origin (no drift); up to 8 per scene; under Reduce flashing the effective rate is at most 3 Hz. MOD-007 left tempo sync to this row. |
| Tempo estimate | ANL-005's beat tracker gives a tempo (BPM) with a confidence 0…1; 0.5 or more is "high". SHOW-011's `TempoSource` takes it (`updateEstimate`) through `TempoCoordinator`'s 250 ms poll. |
| Manual tempo | SHOW-011 tap tempo: 4 taps set a manual tempo (60…200 BPM) that stays until Reset. |
| Combined tempo | Already exists: `TempoSnapshot` (PerformanceControl) is "what every tempo consumer reads" and names MOD-009 as a consumer. Priority: manual if set, else the estimate when its confidence ≥ 0.5 (`TapTempoRules.minimumEstimateConfidence`) and its tempo is in 60…200 BPM, else none. It also carries a beat anchor (last tap or latest analysed beat). The app holds it in `AppCoordinator.tempo.snapshot`. |
| App feed | `NativeSpectrumHost.applyModulation` evaluates the bank once per frame at the frame's display time; `AppCoordinator+LFOs.swift` hands it the scene's oscillators. |
| Scenes | `lfos` entries are kept verbatim (unknown fields included); `invalidLFO`, `unknownLFO` warnings. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An oscillator cycle follows the tempo in beats (Priority: P1)

A scene author sets an oscillator to complete one cycle per a musical length (a quarter beat up to eight
beats) instead of a fixed rate. At 120 BPM a one-beat (quarter-note) cycle lasts exactly 0.5 s and a
four-beat cycle 2 s, so the motion locks to the music.

**Why this priority**: This is the roadmap acceptance.

**Independent Test**: At a fixed 120 BPM, sample a one-beat and a four-beat synced oscillator at t and t +
one period and compare; compare with the closed-form waveform at the tempo's rate.

**Acceptance Scenarios**:

1. **Given** a one-beat synced oscillator at a constant 120 BPM, **When** it is sampled at t and t + 0.5 s,
   **Then** the values are equal within 1e-9, and its quarter-period sample (0.125 s) is the waveform's peak.
2. **Given** a four-beat synced oscillator at 120 BPM, **When** it is sampled at t and t + 2.0 s, **Then**
   the values are equal within 1e-9, and at t + 1.0 s it is half a cycle on.
3. **Given** any allowed length and a constant tempo, **When** it runs for hours, **Then** it matches the
   closed form within 1e-9 (no drift).

---

### User Story 2 - The tempo comes from the right place and changes smoothly (Priority: P1)

The oscillator uses the manual (tap) tempo when one is set, otherwise the detected tempo when the
detection is confident, otherwise its own stored rate. When the tempo changes (a new tap tempo, the
detection drifting, or detection being lost) the motion never jumps: it continues from where it is at the
new speed.

**Why this priority**: A phase jump on a brightness parameter is a visible flash; a wrong tempo source
makes sync useless.

**Independent Test**: Feed the tempo source a manual tempo, a confident estimate and a weak estimate and
check the oscillator's period; change the tempo from 120 to 90 BPM mid-cycle and check continuity.

**Acceptance Scenarios**:

1. **Given** a manual tempo and a confident estimate, **When** the oscillator runs, **Then** it follows the
   manual tempo.
2. **Given** only an estimate with confidence ≥ 0.5, **When** it runs, **Then** it follows the estimate.
3. **Given** only an estimate with confidence below 0.5 (or no tempo), **When** it runs, **Then** it runs at
   its stored rate.
4. **Given** a tempo change from 120 to 90 BPM in the middle of a cycle, **When** frames continue, **Then**
   no frame-to-frame change exceeds what one frame at the faster rate allows, and after the change the
   period is the 90 BPM one (0.667 s for one beat).

---

### User Story 3 - Safe, stored and live in the app (Priority: P2)

Reduce flashing still caps a synced oscillator at 3 cycles per second. A scene stores the sync setting;
an older or newer app keeps settings it does not understand; invalid settings are reported. In the app, a
synced oscillator bound to the glow follows the tap tempo.

**Why this priority**: Safety and persistence make the feature usable; the app test proves the wiring.

**Independent Test**: A quarter-beat oscillator at 240 BPM (16 Hz) with Reduce flashing on runs at 3 Hz;
scene round trip and issue paths; an app unit test with a tapped tempo.

**Acceptance Scenarios**:

1. **Given** a ¼-beat oscillator at 240 BPM and Reduce flashing on, **When** it runs, **Then** it oscillates
   at 3 Hz.
2. **Given** a scene with synced oscillators, **When** it is saved and reopened, **Then** the setting is kept
   exactly; a scene without sync writes nothing new.
3. **Given** an oscillator with a malformed or unknown sync length, **When** the scene opens, **Then** it
   opens, a warning names the path, the oscillator runs at its stored rate and the entry is kept verbatim.
4. **Given** the app with a synced oscillator on the glow and a tapped 120 BPM, **When** frames advance,
   **Then** the effective glow follows a 0.5 s cycle.

### Edge Cases

- A tempo outside 40…240 BPM (or not a finite positive number) is clamped (or ignored when not finite and
  positive); the tempo source itself only reports 60…200.
- Tempo lost (Reset with no confident estimate): the oscillator continues smoothly at its stored rate.
- Reduce flashing turned on or off: a synced oscillator continues smoothly at the new effective rate.
- Time before the origin or a repeated time reads as the last known phase, never as negative time.
- A tempo change on the very first frame: the oscillator starts at its stored phase at that tempo.
- An older app reading a synced oscillator ignores the unknown `sync` field and runs it at its stored rate.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-009-R1**: An oscillator MAY have a sync length in beats per cycle, one of ¼, ½, 1, 2, 4 or 8; any
  other value MUST be refused. One beat is a quarter note.
- **MOD-009-R2**: A synced oscillator's rate MUST be tempo / 60 / beats-per-cycle cycles per second, with
  the tempo clamped to 40…240 BPM; without a usable tempo it MUST run at its stored rate (the fallback).
- **MOD-009-R3**: The tempo MUST be taken in this order: the manual (tap) tempo if set; otherwise the
  detected tempo when its confidence is at least 0.5 (ANL-005's "high"); otherwise none (the fallback).
- **MOD-009-R4**: At a constant tempo the phase MUST be exact as in MOD-007 (within 1e-9 after hours), and
  the value MUST be deterministic for the same sequence of frame times and tempos.
- **MOD-009-R5**: When the effective rate of a synced oscillator changes (tempo, tempo lost or found,
  Reduce flashing), its phase MUST stay continuous: the new rate applies from the phase reached at that
  frame.
- **MOD-009-R6**: Reduce flashing MUST still cap the effective rate at 3 Hz.
- **MOD-009-R7**: A scene MUST store the sync length in an optional `sync` field of the oscillator entry,
  written only when set, with no format version change; unknown fields stay verbatim.
- **MOD-009-R8**: A malformed sync field or an unknown length MUST be reported with a warning at its path;
  the oscillator stays live at its stored rate and the entry is kept for re-save.
- **MOD-009-R9**: The app MUST feed the current tempo (MOD-009-R3) to the scene's oscillators every frame.
- **MOD-009-R10**: The oscillator code MUST stay pure, allocation-free per frame and build on Linux.

### Key Entities

- **Sync length**: beats per cycle (¼…8) of a synced oscillator.
- **Current tempo**: the BPM from the tap tempo or a confident detection, or none.
- **Phase segment**: the frame time, phase and rate from which a synced oscillator continues.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-009-S1**: At 120 BPM a one-beat cycle lasts 0.5 s and a four-beat cycle 2.0 s (samples one period
  apart equal within 1e-9).
- **MOD-009-S2**: The tempo source order holds in all three cases (manual, confident detection, weak or none).
- **MOD-009-S3**: A 120 → 90 BPM change mid-cycle produces no frame-to-frame change larger than one frame
  at the faster rate allows, and the 90 BPM period applies afterwards.
- **MOD-009-S4**: With Reduce flashing on no synced oscillator runs faster than 3 Hz.
- **MOD-009-S5**: Scene round trips keep the sync setting; invalid ones are reported and kept.
- **MOD-009-S6**: In the app a synced oscillator on the glow follows the tapped tempo.
- **MOD-009-S7**: The affected package suites pass on macOS and Linux, each under one minute.

## Assumptions

- No editor UI is added (none exists for oscillators or bindings; MOD-007 decided the same).
- The tempo source's priority and confidence floor are SHOW-011's (`TempoSnapshot`); this row consumes it.
- Square and sample-and-hold shapes remain MOD-008.
