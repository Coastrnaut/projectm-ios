# Feature Specification: ACC-007 Haptic Beat Feedback

**Feature Branch**: `feature/acc-007` (spec directory `238-acc-007-haptic-beat-feedback`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (ACC-007-T01–T12, T14–T16 verified on the Mac: PerformanceControl package tests on the host, app unit and acceptance tests and one UI test on a private iOS 27.2 simulator. Open: ACC-007-T13 `{device}` on D1, since haptics exist only on iPhone hardware. Simulator results are not device evidence.)

**Input**: User description: "Implement ACC-007 (Haptic beat feedback) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Offer optional bounded haptic pulses on selected beat events."
Acceptance, verbatim: "Off setting produces zero haptic calls; high event rate is throttled." P2, depends on ANL-005."

Identifiers in this feature carry the roadmap ID: requirements `ACC-007-R1…`, success criteria `ACC-007-S1…`,
research decisions `ACC-007-D1…`, tasks `ACC-007-T01…`. Other features are cited by their own IDs: ANL-004 (onsets),
ANL-005 (beat tracker), ANL-006 (tempo confidence), ANL-007 (kick transients), ANL-016 (analysis event bus),
SHOW-011 (tap tempo and the app's tempo analysis), MOD-017 (quantized changes: Bar = 4 beats, no downbeat detection),
VIS-006 (beat rings: confident-beat rule), ACC-001 (Reduce Motion), ACC-012 (sensory safety profile), PERF-011
(presentation-bound resources), FILE-005 (library backup), FILE-011 (local data erase).

## Baseline: what exists today (audit of 2026-11-14, commit `c035898f`)

| Question | Today |
|---|---|
| Beat events | ANL-016's bus carries `AnalysisEvent`s: ANL-005 `.beat(bpm:periodSamples:confidence:)`, ANL-007 `.transient(band: .kick, …)`, ANL-004 `.onset`, session markers. Each has `time.hostNanoseconds` on the monotonic bus clock. |
| Who reads them app-wide | SHOW-011 `TempoCoordinator` reads one subscription whatever visual runs: its own `TempoAnalyzer` pipeline under projectM, the native host's pipeline otherwise (`follow(tempoReader)`). It polls every 250 ms on the main actor (`TempoSubscriptionReader.poll()` drains every event). PERF-011 stops it with the presentation. |
| Per-frame bus drains | VIS-006/008/009 drain their own subscriptions per frame in `NativeSpectrumHost` only while those visuals are shown. |
| Confident beats | VIS-006 `BeatRingTrigger`: beats with confidence ≥ `AdaptiveBeatTracker.highConfidence` (0.5). |
| Downbeats | None detected. MOD-017's Bar is every 4th beat from the grid's anchor (4/4, no downbeat detection). |
| Sensory safety | ACC-012 `SafetyClamp` (profile raised by Reduce flashing): flashes per second, rise limit, intensity limit (Standard 1.0, Reduced 0.5, Strict 0.25). ACC-012-R9: "the app has no haptic output … future haptics read the profile"; the Settings footer says "The app uses no haptics." |
| Haptics | None anywhere in the app (no `UIFeedbackGenerator`, no Core Haptics). |
| Settings | `SettingsView.safetySections`: Sensory safety, Reduce flashing. Settings preferences follow the `PowerProfileSetting` pattern (own keys, UI-test reset, FILE-005 list). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Is the feature on by default? → A: No. One Settings switch "Haptic beat pulses", off by default (`ACC-007-R1`). Off installs nothing: no event observer, no haptic generator, the tempo poll keeps its 250 ms (`ACC-007-R2`).
- Q: Which events can pulse? → A: A choice of Beats (ANL-005 beats with confidence ≥ 0.5, VIS-006's rule), Downbeats (every 4th such beat counted from the first beat of an analysis session; 4/4, no downbeat detection, as MOD-017's Bar) or Kicks (ANL-007 kick transients); Beats by default. Onsets, mid and high transients and section changes never pulse (`ACC-007-R3`).
- Q: How strong? → A: Light, Medium or Strong (system impact styles light, medium, heavy), Medium by default (`ACC-007-R1`), scaled by the sensory profile (`ACC-007-R5`).
- Q: Which haptic API? → A: `UIImpactFeedbackGenerator` behind a `HapticPlaying` protocol. A single transient tap per pulse needs nothing Core Haptics adds; Core Haptics' `CHHapticEngine.capabilitiesForHardware()` is used only to learn whether the hardware has haptics (`ACC-007-R6`, research D1).
- Q: What bounds the pulses? → A: Three limits, all on the bus clock: at least 150 ms between pulses, at most 4 pulses in any 1 s, and at most 180 pulses in any 60 s (a duty cycle of 3 per second on average). Events that arrive more than 200 ms after they happened are dropped, never played late (`ACC-007-R4`).

### Session 2026-11-14 (speckit-clarify)

- Q: How does the sensory safety profile apply? → A: Through the effective ACC-012 clamp's intensity limit: each pulse's intensity is that limit (Standard 1.0, Reduced 0.5); at or below Strict's 0.25 no pulse plays at all. Reduce flashing alone (flash part only) changes nothing, as ACC-001-R5 keeps intensity separate (`ACC-007-R5`).
- Q: Low Power Mode? → A: Pulses pause while Low Power Mode is on (conservative: the Taptic Engine costs power and Apple asks apps to cut optional work) and resume when it ends; the stored switch is unchanged and the footer says so (`ACC-007-R6`).
- Q: Background and devices without haptics? → A: Pulses play only while the app is active. On hardware without haptics (iPad) the switch is shown disabled with "This device has no haptics."; the stored value is kept (it travels in backups to an iPhone) (`ACC-007-R6`).
- Q: How do pulses reach the main thread quickly enough? → A: They ride SHOW-011's existing tempo subscription (one bus reader app-wide, PERF-011 lifecycle). While the switch is on, the tempo poll runs every 40 ms instead of 250 ms and hands each drained event to the haptic coordinator; no second pipeline or subscription (`ACC-007-R7`, research D2).
- Q: Stored, backed up, in scenes? → A: Three local preferences (`settings.haptics.beatPulses`, `.beatEvent`, `.strength`), included in the FILE-005 backup and erased with Settings (FILE-011), removed by the UI-test reset; never in scenes, cues, MIDI, OSC or modulation (`ACC-007-R8`, `R9`).

### Session 2026-11-22 (QA-011 device run)

- Q: ACC-007-T13 on D1 (full run 1, the first run on haptic hardware) counted 2 Beats pulses in 12 s (an earlier D1 run: Beats 2, Downbeats 1, Kicks 13); do pulses not fire? → A: The count window was the problem, not the app. It started about 8 s after launch, inside the music fixture's 10 s intro, which has no drums (scripts/make_music_fixture.py), so ANL-005's beats had not reached confidence 0.5 before the window ended, while kicks pulsed in the last seconds of it. Every count (and the Strict and switch-off zeros) now starts once playback reaches 20 s, in the chorus with drums. The fixture's kick falls on every beat, so in the chorus Kicks and Beats give about the same count: the device check for Kicks is now that they pulse with the drums (more than 12 in 12 s), and that only kicks pulse stays ACC-007-S3's host test (QA-011 device run 2026-11-22).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Feel the beat, only when asked (Priority: P1) — MVP

A listener who wants to feel the music turns on Settings → Haptics → Haptic beat pulses, keeps Beats and Medium,
and feels a tap on each confident beat while a visual runs. With the switch off nothing ever taps.

**Why this priority**: it is the roadmap row and both acceptance clauses.

**Independent Test**: a fake player fed a dense synthetic event stream: Off → zero calls; On → one call per
confident beat within the limits.

**Acceptance Scenarios**:

1. **Given** the switch is off, **When** any number of beats, kicks and onsets arrive, **Then** the haptic player receives no call of any kind.
2. **Given** the switch is on with Beats, **When** confident beats arrive at 120 BPM, **Then** each produces one pulse at the chosen strength; low-confidence beats, kicks and onsets produce none.
3. **Given** the switch is on, **When** events arrive at 30 per second, **Then** pulses are never closer than 150 ms, never more than 4 in any 1 s and never more than 180 in any 60 s.

---

### User Story 2 - Choose what pulses (Priority: P2)

A drummer picks Kicks to feel the low end, or Downbeats for one tap per bar; a sensitive user picks Light.

**Independent Test**: the same synthetic stream with each choice gives exactly the selected events' pulses.

**Acceptance Scenarios**:

1. **Given** Downbeats, **When** 8 confident beats arrive in one session, **Then** beats 1 and 5 pulse; a new session restarts the count.
2. **Given** Kicks, **When** beats and kicks arrive, **Then** only kicks pulse.

---

### User Story 3 - Safe and quiet when it should be (Priority: P2)

A user with the Strict sensory profile, a phone in Low Power Mode, an app in the background or an iPad never gets
pulses, and the Settings text says why.

**Independent Test**: the coordinator with each condition set receives a dense stream and makes no call.

**Acceptance Scenarios**:

1. **Given** the Strict profile, **When** beats arrive, **Then** no pulse plays; with Reduced, pulses play at half intensity.
2. **Given** Low Power Mode or an inactive app, **When** beats arrive, **Then** no pulse plays; it resumes when the condition ends.
3. **Given** a device without haptics, **Then** the switch is disabled with "This device has no haptics."

### Edge Cases

- A burst of queued events after a stall (the app was busy): events older than 200 ms are dropped, so no burst of late taps.
- Two pulses' worth of events in the same instant (a beat and its kick under Kicks): the 150 ms interval keeps one.
- The clock: pulses are spaced on the events' own bus times, so the decision is deterministic for a given stream.
- Analysis stops (no visual, presentation lost): no events, no pulses; the downbeat count restarts with the next session.
- The setting is turned off mid-stream: the observer is removed at once; no further calls.
- A Custom profile with intensity limit 0.25 or lower behaves like Strict.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-007-R1**: Settings MUST show a "Haptics" section after Reduce flashing with a switch "Haptic beat pulses" (off by default) and, while it is on, a "Pulse on" choice (Beats, Downbeats, Kicks; Beats by default) and a "Strength" choice (Light, Medium, Strong; Medium by default), with a short footer.
- **ACC-007-R2**: With the switch off the app MUST make zero haptic calls (no generator is created, prepared or played) and MUST NOT change the tempo analysis (no observer, 250 ms poll).
- **ACC-007-R3**: Beats MUST pulse on ANL-005 beats with confidence ≥ 0.5; Downbeats on every 4th such beat counted from the first beat after a session marker (beats that are throttled or dropped still count); Kicks on ANL-007 kick transients. No other event pulses.
- **ACC-007-R4**: Pulses MUST be at least 150 ms apart, at most 4 in any 1 s window and at most 180 in any 60 s window, measured on the events' bus times; an event delivered more than 200 ms after its bus time MUST be dropped.
- **ACC-007-R5**: A pulse's intensity MUST be the effective ACC-012 clamp's intensity limit (1.0 at Standard); at an intensity limit ≤ 0.25 (Strict) no pulse plays.
- **ACC-007-R6**: Pulses MUST play only while the app is active, Low Power Mode is off and the hardware supports haptics. Without haptics the switch MUST be disabled with an explanation and nothing is installed even when the stored choice is on (no observer, 250 ms poll); the stored choice is never changed by these conditions.
- **ACC-007-R7**: Events MUST come from SHOW-011's tempo subscription (no new pipeline or subscription); while the switch is on its poll MUST run every 40 ms; haptic calls MUST run on the main actor, never on the analysis worker or an audio thread.
- **ACC-007-R8**: The three settings MUST be stored locally only, included in the FILE-005 backup, erased with Settings, allowed by `scripts/run_device_tests.py` and removed by the UI-test reset.
- **ACC-007-R9**: The settings MUST NOT be recorded in scenes or cues, set by MIDI or OSC, or modulated.
- **ACC-007-R10**: ACC-012's Sensory safety footer MUST no longer say the app uses no haptics; it MUST say that haptic pulses follow the profile.
- **ACC-007-R11**: The controls MUST carry VoiceOver labels and identifiers (`hapticBeatToggle`, `hapticBeatEventPicker`, `hapticBeatStrengthPicker`) and work at every Dynamic Type size.

### Key Entities

- **Haptic beat setting**: enabled, event choice (beats, downbeats, kicks), strength (light, medium, strong).
- **Pulse gate**: the pure decision per event: filter by choice, count downbeats, drop stale events, apply the three rate limits.
- **Haptic player**: what plays a pulse (`HapticPlaying`): the system impact generator, or a fake in tests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-007-S1**: Off: a 60 s synthetic stream at 30 events per second (beats, kicks, onsets) produces 0 player calls.
- **ACC-007-S2**: On (Kicks) with kicks at 30 per second for 60 s: every gap between pulses ≥ 150 ms, no 1 s window holds more than 4 pulses, the 60 s holds at most 180, and the result is identical on a second run (deterministic with an injected clock).
- **ACC-007-S3**: Each choice pulses exactly on its events (Beats: confident beats only; Downbeats: beats 1, 5, 9…; Kicks: kicks only).
- **ACC-007-S4**: Strict, Low Power Mode, an inactive app and missing hardware each produce 0 calls over the S1 stream; Reduced plays at intensity 0.5.
- **ACC-007-S5**: A UI test turns the switch on and off in Settings in under 30 s; the choices appear only while it is on.

## Assumptions

- Haptics exist only on iPhone hardware; the simulator and iPads have none, so feel and latency are checked on D1 (`{device}` task). Simulator results are never device evidence.
- ANL-005's beats are as good as the analysis; this feature adds no detection (Constitution VIII: no duplicate analysis).
- The 40 ms poll while on adds at most 40 ms to the analysis latency; the pulses are a felt cue, not sample-accurate.
