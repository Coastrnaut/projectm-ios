# Feature Specification: ANL-015 Section Energy Change

**Feature Branch**: `feature/anl-015` (spec directory `202-anl-015-section-energy-change`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row ANL-015 (docs/FEATURE_ROADMAP_AUTONOMOUS.md), verbatim: "Detect sustained
transitions between quiet and loud sections." Acceptance, verbatim: "Quiet-to-loud fixture triggers
one change event after dwell time." P2, size M, depends on ANL-014 (integrated). Marked "Gap
candidate; re-audit at implementation". Verification: "Accelerate/vDSP, deterministic sample clocks;
unit with synthetic PCM + simulator". The brief adds: a slow energy measure compared against a longer
baseline; a change event (quiet→loud or loud→quiet) only after the new level persists for a dwell
time, with hysteresis and a refractory period so one transition fires exactly once; sample-clock
based, deterministic, chunking-invariant and NaN-safe; exposed as an event or trigger source others
can use; brief bursts shorter than the dwell fire nothing.

Identifiers carry the roadmap ID: requirements `ANL-015-R1…`, success criteria `ANL-015-S1…`, tasks
`ANL-015-T01…`. Other features are cited by their own IDs: ANL-014 (loudness envelope, whose
per-frame level this feature reads), ANL-016 (analysis event bus), ANL-013 (stereo correlation, the
pattern followed for a held, hysteretic state on the bus), ANL-007 (kick envelope, the pattern for
an event-driven decaying source), MOD-002 (audio feature sources and bindings), SHD-009 (expressions
that read audio sources), UIX-003 (parameter inspector names), ACC-011 (status events).

## Baseline: what exists today (audit of 2026-11-14, commit `2cf81d9d`, ANL-013 integrated)

The audit confirms the gap: nothing in `Packages/` or `Apps/` detects a change of section or of
sustained level.

| Area | Today | Gap for this row |
|---|---|---|
| Level | ANL-014 computes, per analysis frame (2,048-sample window every 512 samples at 44.1 kHz), the frame's unsmoothed K-weighted level `loudnessDecibels` (LKFS-like dB, −120 at silence; recorded as "for ANL-015's later section-change detector") and a smoothed 0…1 envelope (attack 100 ms, release 400 ms). | A 100/400 ms envelope follows beats, not sections; nothing holds a longer reference or decides that a level change has lasted. |
| Bus | ANL-016's `AnalysisFrame` (per frame) and `AnalysisEvent` (onset, beat, transient, session markers), one sample clock, strictly increasing IDs. | No section-change event, no field. |
| Modulation | MOD-002 sources up to `audio.correlation` (SHD-009 opcode 34); `audio.kick` is the pattern for an event that triggers a decaying 0…1 value. Opcodes 35 and above are free on `autonomous/integration` and every feature branch. | No source a visual can use to react to a section change. |
| Status | ACC-011's router carries system status (source, capture, recording…). | Not applicable: a musical section change is content, not app status (see Clarifications). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: decisions delegated, no
human interaction); each answer is the recommended, conservative option.

- Q: What level does the detector read? → A: ANL-014's per-frame K-weighted level (`loudnessDecibels`) inside the ANL-016 pipeline, on every spectrum frame: no second level measure, no extra FFT, the same audio (after AUD-009, AUD-008, AUD-011) every bus feature sees. A frame below the detector's floor (−70 dB) or non-finite counts as the floor, so silence is one steady "very quiet" level, never −120 swings or NaN (ANL-015-R1, R7).
- Q: What is the slow energy measure? → A: The mean K-weighted power of the last 35 frames (35 × 512 = 17,920 samples ≈ 0.41 s at 44.1 kHz, ITU-R BS.1770's 400 ms "momentary" span), converted back to dB. Averaging power (not dB) rates a loud passage by its energy, and a rectangular window is symmetric: a level change is seen within one or two frames when it starts (a 30 dB rise shows in the first frames that hold it) and is forgotten 0.41 s after it ends. A one-pole smoother was rejected: in dB it delays the start of a rise by tens of milliseconds (pushing the event outside "one block after the dwell"), and in power it releases slowly, so a 1 s burst would read loud for 3-4 s and fire (ANL-015-R2).
- Q: What is the longer baseline? → A: A reference level R in dB, the level of the current section. It is seeded during a settling period (the first 2.0 s of each session, R = the slow level, no events, so the session's opening level is not itself a "change"), then follows the slow level with a one-pole time constant of 8 s (a = 1 − exp(−512 / (8 · 44,100)) per frame) while no change is pending, so a slow crescendo or fade is absorbed instead of firing. R is frozen while a change is pending and set to the slow level when one fires (ANL-015-R3).
- Q: Thresholds, hysteresis and dwell? → A: A change becomes pending when the slow level is at least 6 dB above (rising) or below (falling) R; it stays pending while it remains more than 3 dB beyond R in the same direction (the hysteresis band) and is cancelled the first frame it does not. It fires on the first frame whose window end is at least the dwell, 2.0 s (88,200 samples), after the frame that started it. 6 dB is a doubling of amplitude, clearly audible as a new section; 3 dB keeps a pending change alive through a loud section's dips between hits; 2 s is about one bar at 120 bpm, so a fill, a drop hit or a shout does not count as a section (ANL-015-R4).
- Q: Refractory period? → A: 4.0 s after a change fires, no new change can become pending (R keeps following the slow level at 8 s). With R set to the new level at the event this makes one transition fire exactly once even when the new section keeps settling; a reverse change during the refractory period is detected after it if it lasts (ANL-015-R5).
- Q: What does "within one block after the dwell" mean, and where is the event placed? → A: One block is one ANL-016 analysis window (2,048 samples, 46 ms): the change is first seen on the frame whose window holds enough of the new level, and the event is published on the first frame at or past the dwell from it, so for a quiet-to-loud step at sample s the event's frame ends in [s + dwell, s + dwell + 2,048]. The event's `time` is that confirming frame's timestamp; its `eventSample` is the window end of the frame that started the change (where the new section was first seen), at most `time.sessionSample` as ANL-016 requires (ANL-015-R6).
- Q: How do bursts behave? → A: The slow measure holds a burst for its length plus up to 0.41 s, so a loud burst shorter than dwell − 0.41 s ≈ 1.59 s never fires; tests use 1.0 s and 1.5 s bursts (ANL-015-R4, S2).
- Q: How is it exposed? → A: Three ways. (1) A discrete bus event `AnalysisEventKind.sectionChange(direction:levelDecibels:referenceDecibels:)` (direction `.rising` = quiet→loud, `.falling` = loud→quiet; the slow level and the old reference in dB), published after the frame's other events. (2) Two frame fields: `sectionChangeEnvelope` (1 on the event's frame, decaying with a 1.0 s time constant on the sample clock, exactly 0 below 0.001; same shape as ANL-007's kick) and `sectionLevelDecibels` (the slow level, for readouts). (3) MOD-002 source "Section change", stable ID `audio.sectionChange`, reading the envelope (missing or non-finite reads 0), SHD-009 opcode 35 (34 = correlation; 35 is free on `autonomous/integration` and every feature branch), inspector name "Section change". The native visual feeds it to its bindings like the kick (ANL-015-R8 to R10).
- Q: Is a change announced or shown as status? → A: No. A section change is musical content, like a beat or a kick, not app status: ACC-011's router carries status the user must know about (source, capture, warnings), and announcing every section change would be noise for VoiceOver users. No status event, no overlay line, no setting (ANL-015-R12).
- Q: Backend and determinism? → A: A portable Float/Double loop over 35 stored frame powers per frame (no vDSP needed at that size), so it is identical on the vDSP and portable backends and in the Linux shape (`-DANALYSIS_NO_ACCELERATE`). The input is per frame and frames depend only on the sample sequence, so results are bit-equal across chunkings; no clock is read. The 35-entry history is allocated once when the detector is created and written in place (one owner, never copied): processing allocates nothing (ANL-015-R7, R11).
- Q: Session starts? → A: A session start (attach, restart, source restart) resets everything: history, reference, settling, pending change, refractory and envelope (ANL-015-R7).
- Q (speckit-clarify pass): Stored data or settings? → A: None. A binding stores only `audio.sectionChange` (older builds orphan it, MOD-013); no scene version bump, no UserDefaults key, no Settings row (ANL-015-R12).
- Q (implementation finding): How many events does a long fade fire? → A: The 8 s reference absorbs a drift whose steady lag (slope × 8 s) stays under the 6 dB entry threshold, i.e. slower than about 0.75 dB/s: no event. A faster fade (the test's 40 dB over 10 s, 4 dB/s) is a real level change and fires a rising event each time the lag reaches 6 dB again, no closer together than dwell + refractory (6 s): two events for that fade. Accepted as correct (each event marks a ≥ 6 dB sustained rise); the earlier "at most one" wording was replaced (ANL-015-R3 to R5).
- Q (speckit-clarify pass): Should a held "current section is loud/quiet" value also be a binding source? → A: No. A held state needs a definition of absolute loud and quiet that the relative detector does not have (a quiet section of a loud master can be louder than a loud section of a quiet one); the triggered envelope plus the event's direction cover reacting to a change, and ANL-014's Loudness source already gives the level. One source keeps the opcode space and the inspector small (ANL-015-R9).
- Q (speckit-clarify pass): What do the frame fields read before any signal and during settling? → A: The slow level reads the floor (−70 dB) until frames with signal arrive, and the envelope 0; both are always finite. A session start resets them (ANL-015-R7, R8).
- Q (speckit-clarify pass): Test cost? → A: Fixtures of at most 12 s of synthetic audio through the per-frame detector (a few thousand frames) and one pipeline run of about 8 s (owner rule 7: each test under 2 s on the host).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A quiet-to-loud change fires once, after the dwell (Priority: P1)

A visual author wants a visual to react when the music moves from a quiet section into a loud one
(a chorus, a drop): exactly one trigger, shortly after the new section has clearly established
itself, not on every hit.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed synthetic PCM (quiet tone, then loud tone) on a deterministic sample clock and collect events.

**Acceptance Scenarios**:

1. **Given** 4 s of a −40 dBFS tone then 6 s of a −10 dBFS tone, **When** analysed, **Then** exactly one quiet→loud event fires, on a frame ending no earlier than step + dwell and no later than step + dwell + one analysis window.
2. **Given** the same fixture split into different chunk sizes, **When** analysed, **Then** the events are identical.

---

### User Story 2 - Brief bursts and steady music fire nothing (Priority: P1)

**Why this priority**: False triggers would make section-driven visuals flicker on every fill.

**Acceptance Scenarios**:

1. **Given** a quiet tone with a 1.0 s or 1.5 s loud burst, **When** analysed, **Then** no event fires.
2. **Given** a steady tone, steady noise or silence throughout, **When** analysed, **Then** no event fires.
3. **Given** a slow drift (10 dB over 20 s), **When** analysed, **Then** no event fires; **given** a fade-in (−50 to −10 dB over 10 s), **Then** only rising events fire, at least dwell + refractory apart (at most two).

---

### User Story 3 - Loud-to-quiet also fires once; bad input is calm (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a loud tone then a quiet tone (or silence), **When** analysed, **Then** exactly one loud→quiet event fires after the dwell.
2. **Given** input containing NaN or ±∞ samples or levels, **When** analysed, **Then** every value is finite and the envelope stays in 0…1.

---

### User Story 4 - Section change is a modulation source (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the real analysis pipeline fed quiet then loud audio, **When** frames and events are read, **Then** exactly one section-change event arrives and the frames' envelope is 1 on that frame and decays afterwards.
2. **Given** the native visual with a "Section change" binding, **When** frames carry the envelope, **Then** the bound parameter follows it, and the inspector names the source "Section change".

### Edge Cases

- A step during the first 2 s of a session is absorbed into the settling reference: no event (the opening level is not a change).
- Silence to music after settling: a rising change (silence reads as the −70 dB floor).
- A second step in the same direction during the refractory period: detected after it if it still differs by 6 dB from the reference then.
- A reverse change during the refractory period: detected after it if it lasts.
- Levels between 3 and 6 dB away from the reference: never start a change; a slow drift is absorbed by the 8 s reference.
- A session restart clears the history, reference, pending change and envelope.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-015-R1**: The system MUST read, per analysis frame, ANL-014's unsmoothed K-weighted level; values below the floor (−70 dB) or non-finite MUST count as the floor.
- **ANL-015-R2**: The slow level MUST be the decibel value of the mean power of the last 35 frames (≈ 0.41 s).
- **ANL-015-R3**: The reference MUST be seeded from the slow level during the first 2.0 s of a session, follow it with an 8 s time constant while no change is pending, be frozen while one is pending, and be set to the slow level when one fires.
- **ANL-015-R4**: A change MUST become pending when the slow level is at least 6 dB beyond the reference, stay pending while it remains more than 3 dB beyond it in the same direction, be cancelled otherwise, and fire once the dwell (2.0 s, counted in samples from the frame that started it) has elapsed.
- **ANL-015-R5**: For 4.0 s after a change fires, no new change may become pending.
- **ANL-015-R6**: A change MUST be published as a bus event with its direction, the slow level and the previous reference, timed at the confirming frame, with `eventSample` the window end of the starting frame.
- **ANL-015-R7**: Results MUST be deterministic, independent of chunking and backend, read no clock, and reset at every session start.
- **ANL-015-R8**: Every feature frame MUST carry the section-change envelope (1 on an event frame, decaying with a 1.0 s time constant, 0 below 0.001, within 0…1) and the slow level in dB.
- **ANL-015-R9**: MOD-002 MUST offer `audio.sectionChange` reading the envelope (missing or non-finite reads 0), usable in bindings, scenes and SHD-009 expressions through permanent opcode 35; the inspector MUST name it "Section change".
- **ANL-015-R10**: The app's native visual MUST feed the envelope to its bindings.
- **ANL-015-R11**: Processing MUST NOT allocate, lock, log or do I/O (Constitution VII), and MUST build and pass its tests in the Linux shape (`-DANALYSIS_NO_ACCELERATE`).
- **ANL-015-R12**: Nothing here reaches projectM (Constitution VIII); no new setting, stored key, status event, network or UI beyond the inspector's source name.

### Key Entities

- **Section change configuration**: sample rate, hop, window frames, floor, settle, reference time constant, enter and hold thresholds, dwell, refractory, envelope time constant.
- **Section change event**: direction (rising or falling), slow level and previous reference in dB, start and confirmation samples.
- **Section reading**: slow level, reference, whether a change is pending, the envelope.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-015-S1**: The quiet-to-loud fixture fires exactly one rising event, on a frame ending within [step + dwell, step + dwell + one analysis window] (the roadmap acceptance).
- **ANL-015-S2**: 1.0 s and 1.5 s bursts, a step inside the settling period, steady tone, jittering level, silence and a 0.5 dB/s drift fire nothing; a 4 dB/s fade fires only rising events at least dwell + refractory apart.
- **ANL-015-S3**: The loud-to-quiet fixture fires exactly one falling event after the dwell.
- **ANL-015-S4**: Repeats and different chunkings give identical events; non-finite input keeps every value finite and the envelope in 0…1.
- **ANL-015-S5**: Through the real pipeline, the quiet-to-loud fixture yields exactly one section-change event, and the envelope is 1 on its frame and lower afterwards.
- **ANL-015-S6**: `audio.sectionChange` round-trips, binds, compiles to opcode 35 and drives a bound parameter in the app; the inspector reads "Section change".
- **ANL-015-S7**: The new package tests take under 2 s each on the host; every existing test passes.

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz; the detector is valid at any hop and rate it is configured for (the window of 35 frames is fixed in frames, so at other hops its span changes; documented in the contract).
- "Section" means a sustained level change, not a structural analysis of the song (no verse/chorus labels, no repetition detection).
- Acceptance is synthetic PCM (unit tests); simulator results are not device evidence. Real music is a device observation.
- The detector runs only while a native visual (which runs the ANL-016 pipeline) is shown; projectM does not run the analysis bus.
