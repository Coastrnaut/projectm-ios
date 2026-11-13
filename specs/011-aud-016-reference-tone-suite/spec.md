# Feature Specification: AUD-016 Reference tone suite

**Feature Branch**: `feature/aud-016` (spec directory `011-aud-016-reference-tone-suite`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement AUD-016 (Reference tone suite) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Provide opt-in locally generated
sine, sweep, pulse and silence inputs for diagnostics." Acceptance, verbatim: "Fixtures reproduce
identical FFT and beat outputs on repeated runs." Dependencies: none (extends the existing reference
playback). Honor the repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-016-R1…`, success criteria `AUD-016-S1…`, tasks `AUD-016-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`, in particular FR-006, FR-013, FR-015,
FR-069 and FR-070), of AUD-001 (`specs/003-…`), AUD-006 (`specs/007-…`) and AUD-014 (`specs/009-…`)
stay in force. This feature cites them and adds to them.

## Clarifications

### Session 2026-11-12

Answered by Claude under the owner's standing approval (routine decisions delegated, no human
interaction); each answer is the conservative, local-first option using public APIs only.

- Q: Where does the user find the test signals: in the source chooser or in Settings? → A: In the source chooser, as a "Diagnostics" section after "Your Audio" whose single row opens the signal list. Every source starts from the chooser and Settings is reachable only while a source already runs; a separate list keeps the signals out of the way of music and imported tracks (AUD-016-R13).
- Q: At what sample rate does a picked signal play? → A: At the catalog's canonical rate, 48 kHz, always. The played samples are then exactly a catalog variant with a known golden hash; when the output runs at another rate iOS converts, and the analysis sees the converted signal within the documented tolerance. Generating at whatever rate the device reports would make the played samples depend on the route (AUD-016-R23, R20).
- Q: How loud may a test signal be? → A: No sample above −6 dBFS (0.5 of full scale): steady tones and sweeps at 0.25 (−12.04 dBFS), pulse peaks at 0.5. The list's footer asks the user to lower the volume first. Full-scale clicks like the reference track's are not needed for analysis and are unpleasant on headphones (AUD-016-R7, R13).
- Q: Is the picked signal remembered, for example as the next launch's source? → A: No. Nothing about the Diagnostics list is stored; each relaunch starts at the chooser with no signal selected, and no new stored data is added, so the privacy policy and privacy manifest do not change (AUD-016-R14).
- Q: May the generator use the platform's sine, exponential and logarithm functions if the golden hashes happen to match on this Mac? → A: No. The generator uses only correctly rounded basic arithmetic (addition, subtraction, multiplication, division, exact scaling by powers of two and rounding to whole numbers) and its own fixed polynomial approximations of sine, exponential and logarithm, because platform math libraries may differ between macOS, iOS and Linux in the last bit. The golden hashes on the Mac host and the iOS Simulator are the check (AUD-016-R3).

## Baseline: what exists today (audit of 2026-11-12, commit `97d7949`)

This is an extension row ("Extension (existing reference playback)").

| Area | Today | Gap for this row |
|---|---|---|
| Reference audio | `scripts/generate_reference_audio.py` writes one fixed 60 s, 44.1 kHz stereo WAV (tones, silence, a 120 BPM beat, clicks) that is bundled and played as the In-App Playback reference track. Its bytes are identical on every run. | One fixed track. No way to choose one signal alone, no other rates or channel layouts, no sweep, no accent pattern, no documented expected analysis values per signal, and no generator the app's own code or tests can call. |
| Playback | In-App Playback plays the reference track or an imported file through one graph, with the AUD-006 transport and the AUD-014 interruption policy. Every track is a file. | No in-memory, generated content. |
| Analysis | Peak and RMS levels and the audio-state classifier exist. There is no FFT, onset or beat analysis (ANL-001, ANL-004, ANL-005 are later rows). | The "identical FFT and beat outputs" check cannot run yet; this row delivers the fixtures and the expected values those rows will check against. |
| Diagnostics | CaptureLab and the user-initiated diagnostics export record metadata only. | No diagnostic signal the user can pick in the visualizer app. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Check the visualizer with a known signal (Priority: P1)

A user (or a tester, or support helping a user) wants to know whether the visualizer reacts
correctly, independent of any music or capture source. In the source chooser they open a clearly
labeled Diagnostics place, pick a test signal (a steady sine tone, a frequency sweep, a pulse train
at a known tempo, or digital silence) and the visualizer starts with that signal as its input. The
status line names the signal truthfully as a generated test tone played by the app, never as
captured or imported audio. Nothing plays until they pick a signal, and the choice is not
remembered after the app quits.

**Why this priority**: It is the row's observable behavior. It also gives the later analysis and
visual rows a reproducible input on a real device.

**Independent Test**: Launch the app, open the Diagnostics place in the chooser, pick each signal in
turn and read the status line, the transport title and the audio state.

**Acceptance Scenarios**:

1. **Given** the source chooser, **When** the user does nothing, **Then** no test signal plays and the
   three sources and "Your Audio" look as before; the Diagnostics place is listed after them, labeled
   as test signals and not as music.
2. **Given** the Diagnostics place is open, **When** the user picks "Test tone 1 kHz", **Then** the
   visualizer starts, the status line reads "In-App Playback · Test tone 1 kHz · <state>" and becomes
   "Active audio" only after non-silent audio was verified (FR-010, Constitution IV).
3. **Given** the user picks "Test silence", **When** the visualizer runs, **Then** the status line
   reads "In-App Playback · Test silence · Audio received — silent".
4. **Given** a test signal is playing, **When** the user stops, quits and relaunches the app, **Then**
   the chooser is shown and no test signal starts by itself.

---

### User Story 2 - Identical fixtures on every run (Priority: P1)

A developer writing an analysis feature (FFT, bands, onsets, beat tracking) or a test needs input
signals whose samples are exactly the same on every run, on the Mac and in the iOS Simulator, at the
sample rates and channel layouts the app supports, with documented expected analysis values (which
frequency bin a tone falls into, at which sample each pulse starts, which tempo a pulse train has,
what frequency a sweep has at a given moment).

**Why this priority**: It is the row's acceptance: identical analysis outputs require identical
inputs first, and the expected values are what the later rows assert against.

**Independent Test**: Generate every catalog fixture twice and in every rate and layout variant,
compare each against a stored SHA-256 golden hash, on the Mac and in the iOS Simulator; check the
documented expected values against an independent reference computation in the tests.

**Acceptance Scenarios**:

1. **Given** the fixture catalog, **When** every fixture is generated twice in the same process,
   **Then** the two outputs are identical bit for bit and match the stored golden hash.
2. **Given** the same catalog, **When** it is generated on the Mac and in the iOS Simulator, **Then**
   every hash matches the same stored golden value.
3. **Given** a sine fixture and an FFT size from 512 to 8192, **When** a reference transform is
   computed in the tests, **Then** the largest magnitude is at the documented bin.
4. **Given** a pulse fixture, **When** a reference onset scan is run in the tests, **Then** it finds
   exactly the documented onset sample indices and the documented tempo.
5. **Given** a sweep fixture, **When** its local frequency is measured in the tests, **Then** it matches
   the documented instantaneous frequency within the stated tolerance.

---

### User Story 3 - The tone reaches the analysis unchanged (Priority: P2)

The test signal the user picks travels the same path as any In-App Playback track. A developer
needs to know that what reaches the app's analysis is the generated signal itself, so that later
analysis results can be traced back to the fixture.

**Why this priority**: Without it, a test signal proves nothing about the pipeline.

**Independent Test**: Play fixtures through the production playback path rendered offline and
compare what reaches the analysis input with the generator's output, twice.

**Acceptance Scenarios**:

1. **Given** a fixture whose rate equals the output rate, **When** it is played through the
   production path, **Then** every delivered frame equals the generated frame exactly (a mono
   fixture appears identically on both output channels).
2. **Given** a fixture whose rate differs from the output rate, **When** it is played, **Then** the
   delivered audio matches the fixture within the documented conversion tolerance.
3. **Given** the same fixture played twice, **When** the delivered audio is compared, **Then** both
   runs are identical.
4. **Given** the existing level meter and audio-state classifier, **When** each fixture is fed through
   them twice with the same deterministic clock, **Then** the levels and states are identical on both
   runs and match the documented values (a sine is active, silence is silent).

---

### User Story 4 - Transport and interruptions behave sensibly for an endless tone (Priority: P3)

While a test signal plays, the user uses the transport and iOS interrupts audio as it does for any
track. The signal is a short loop that repeats without a gap; seek moves within the loop, Previous
and Next start the loop again, Stop playback silences it at 0:00, Play continues it, and the
interruption policy of AUD-014 applies unchanged.

**Why this priority**: The behavior must be predictable, but the transport is secondary for a test
signal.

**Independent Test**: Start a fixture through the production backend rendered offline, seek, pause,
resume, deliver a synthetic interruption, and check positions and delivered frames.

**Acceptance Scenarios**:

1. **Given** a test signal is playing, **When** the transport is shown, **Then** its title is the
   signal's name and its length is the loop's length (10 seconds).
2. **Given** a test signal is playing, **When** the user seeks to 4.0 s, **Then** the first delivered
   frame after the seek is the fixture's frame at 4.0 s.
3. **Given** a test signal at the end of its loop, **When** playback continues, **Then** it repeats
   from frame 0 without a gap and never reports an end.
4. **Given** a test signal, **When** Previous track or Next track is pressed, **Then** the same signal
   starts again from 0:00; no other track or signal plays.
5. **Given** a test signal is interrupted (AUD-014), **When** the interruption ends with a resume
   indication, **Then** it continues from the held frame exactly as a track would.

### Edge Cases

- A generator parameter outside its bounds (frequency above the Nyquist limit or below 1 Hz, an
  amplitude above full scale or negative, a rate outside 8 kHz to 192 kHz, a channel count other
  than 1 or 2, a pulse width longer than the pulse period, an empty accent pattern, a zero or
  negative duration) is rejected with a typed error; nothing is generated or played.
- A sweep whose end frequency equals its start frequency is a steady tone; a logarithmic sweep
  needs both frequencies above 0.
- A pulse tempo that does not divide the sample rate evenly puts each onset at the nearest sample
  of its exact time, never accumulating drift.
- A test signal cannot be generated (memory): the session ends as "In-App Playback failed"
  (FR-015); no other track plays instead (AUD-001-R19).
- Media services reset while a test signal plays: the signal is generated again and continues from
  the held frame (AUD-014-R16); because generation is deterministic it is the same signal.
- The output rate differs from the fixture's rate: iOS converts; analysis then sees a converted
  signal, documented with a tolerance, not bit-exact.
- VoiceOver: every Diagnostics row has a label (the signal's name) and a hint (what it plays).

## Requirements *(mandatory)*

### Functional Requirements

**Generator**

- **AUD-016-R1**: The app MUST include a local signal generator that produces sine, sweep
  (logarithmic and linear), pulse-train and digital-silence signals, mono or stereo, at any whole
  sample rate from 8,000 Hz to 192,000 Hz. Nothing is downloaded or read from disk to make a signal.
- **AUD-016-R2**: Generator output MUST be a pure function of the signal's parameters, the sample
  rate, the channel layout and the frame index: no wall clock, no randomness, no state carried
  between calls. Generating any range of frames on its own MUST give the same samples as the same
  range inside a longer generation.
- **AUD-016-R3**: Generator output MUST be bit-identical on every run and on every supported host
  (macOS host tests, iOS Simulator, iOS devices, and the Linux package build). It MUST NOT depend on
  the platform's math library for any value that reaches a sample: only correctly rounded basic
  arithmetic and the generator's own fixed approximations are used (Clarifications).
- **AUD-016-R4**: Sine: frequency, amplitude and per-channel settings (each channel of a stereo
  signal may have its own frequency, or be silent).
- **AUD-016-R5**: Sweep: start and end frequency, duration, amplitude, logarithmic or linear; phase
  is continuous within the sweep.
- **AUD-016-R6**: Pulse train: tempo in beats per minute (or pulses per second), pulse width,
  amplitude, an optional accent pattern of per-beat amplitude factors; onset `k` starts at the sample
  nearest to `k × 60 / BPM` seconds.
- **AUD-016-R7**: Every parameter MUST be bounded and validated (Edge Cases); invalid parameters
  return a typed error naming the parameter. Catalog fixtures never exceed 0.5 of full scale
  (−6 dBFS); steady tones and sweeps use 0.25.
- **AUD-016-R8**: The generator MUST be able to write into caller-provided storage without
  allocating, so a consumer may stream it on a real-time path (Constitution VII).

**Fixture catalog**

- **AUD-016-R9**: A versioned catalog MUST name a fixed set of fixtures (at least one per signal
  kind, including a stereo sine with different channels, an accented pulse train and a pulse tempo
  whose period is not a whole number of samples). Each fixture has a stable ID, a display name, its
  parameters and a loop length of 10 seconds.
- **AUD-016-R10**: For each fixture and each supported variant (44.1 kHz and 48 kHz; mono and stereo
  where the fixture allows both), the catalog's documentation MUST record the SHA-256 of the
  generated samples (32-bit float, little-endian, interleaved, one loop), and tests MUST compare
  against it. Changing a fixture's samples MUST change the catalog version.
- **AUD-016-R11**: The catalog MUST document expected analysis values, computed from the parameters
  alone: for each sine the exact and the nearest FFT bin for FFT sizes 512, 1024, 2048, 4096 and
  8192 at 44.1 kHz and 48 kHz, and whether the tone is centered on a bin; for each pulse train the
  onset sample indices of one loop, the tempo, the inter-onset interval and the accent of each
  onset; for each sweep the instantaneous frequency at 0, 2.5, 5 and 7.5 seconds; for silence that
  every sample is zero.
- **AUD-016-R12**: The tests MUST check the expected values against an independent reference
  computation written in the tests only (a straightforward discrete Fourier transform at small sizes
  and a straightforward onset scan). The reference computation MUST NOT ship in the app.

**Playback and UI**

- **AUD-016-R13**: The source chooser MUST offer a "Diagnostics" section after the sources and
  "Your Audio", with one entry that opens the list of test signals. Each list row shows the signal's
  name and a one-line description; the list explains that the signals are generated on the device
  for testing, are not music, and that the user may want to lower the volume.
- **AUD-016-R14**: Nothing plays until the user picks a signal. The choice MUST NOT be stored: after
  a relaunch the app behaves as if no signal had ever been picked. No test signal is ever the
  default source. The feature adds no stored data of any kind.
- **AUD-016-R23**: A picked signal plays at the catalog's canonical rate of 48 kHz in stereo, so
  the played samples are exactly the catalog's 48 kHz stereo variant.
- **AUD-016-R15**: A picked signal MUST play as In-App Playback through the same playback path as
  every other In-App track (the AUD-006 transport and the AUD-014 interruption policy apply), and it
  is never labeled System/App Capture or Microphone (Constitution IV).
- **AUD-016-R16**: While a test signal plays, the source-and-state indicator MUST read
  "In-App Playback · <signal name> · <state>" and the transport title MUST be the signal's name. Each
  signal's name starts with "Test" so it cannot be taken for music. For every other track the
  indicator is unchanged (FR-013).
- **AUD-016-R17**: A test signal is one loop of its fixture (10 seconds) that repeats without a gap
  and never ends. Seek moves within the loop; Previous track and Next track start the same signal
  again at 0:00; Stop playback silences it at 0:00 and Play continues it (AUD-006-R5).
- **AUD-016-R18**: A signal that cannot be generated or loaded MUST end the session as "In-App
  Playback failed"; no other track or signal plays instead.
- **AUD-016-R19**: The signal is generated in memory when it starts and handed to the player
  before playback; nothing is generated, allocated or locked on the audio render thread for it
  (Constitution VII). The signal is never written to disk.
- **AUD-016-R20**: The played audio at the output rate MUST equal the generator's output exactly
  when the rates match, and match within the documented conversion tolerance otherwise (US3).

**Determinism of today's analysis**

- **AUD-016-R21**: Feeding a fixture through the existing level meter and audio-state classifier
  in fixed blocks with a deterministic clock MUST give identical levels and states on repeated runs.

**Hand-off to the analysis rows**

- **AUD-016-R22**: The spec, the catalog and the generator are the inputs of ANL-001 (FFT), ANL-002
  (bands), ANL-004 (onsets), ANL-005 (beat tracker), ANL-016 (event bus) and QA-001 (deterministic
  fixtures). Those rows MUST add to their own acceptance tests that their outputs for these fixtures
  are identical on repeated runs (see Hand-off below).

### Key Entities

- **Tone signal**: a kind (sine, sweep, pulse train, silence) with its bounded parameters.
- **Tone format**: sample rate (whole Hz, 8 kHz to 192 kHz) and channel count (1 or 2).
- **Reference tone fixture**: catalog ID, display name, description, signal, loop length, the
  variants it supports, and per variant its golden SHA-256.
- **Expected values**: per fixture, the analysis values computed from its parameters (bins, onsets,
  tempo, instantaneous frequencies).
- **Diagnostic tone track**: a fixture chosen as the In-App Playback track for one session; not
  stored.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-016-S1**: 100% of catalog fixtures in every listed variant reproduce their stored hash on two
  consecutive runs on the Mac host and in the iOS Simulator (and in the package build without the
  system audio framework).
- **AUD-016-S2**: For every sine fixture and FFT size 512 to 8192 checked by the reference
  transform, the peak is at the documented nearest bin in 100% of cases.
- **AUD-016-S3**: For every pulse fixture, the reference onset scan finds 100% of documented onsets
  at exactly the documented sample, with no extra onsets.
- **AUD-016-S4**: For every sweep fixture, the measured local frequency at the documented times is
  within 1% of the documented value.
- **AUD-016-S5**: Played through the production path at a matching rate, 100% of delivered frames
  equal the generated frames; at a different rate the delivered signal stays within the documented
  tolerance; two runs give identical delivered audio.
- **AUD-016-S6**: Level and state results of the existing analysis are identical on two runs for
  100% of fixtures.
- **AUD-016-S7**: A user can start any test signal from the chooser in at most 2 taps after the
  chooser opens, and no test signal starts without a tap.
- **AUD-016-S8** `{device}`: On D1, D2 and D3, each signal kind plays audibly on the built-in speaker
  and on headphones, the status reaches "Active audio" (silence: "Audio received — silent"), and an
  interruption and a route change behave as for an imported track (final device phase).

## Hand-off to ANL-001, ANL-002, ANL-004, ANL-005, ANL-016 and QA-001

The roadmap's acceptance for this row is "Fixtures reproduce identical FFT and beat outputs on
repeated runs". The FFT (ANL-001) and the beat tracker (ANL-005) do not exist yet, so this row
delivers the part it owns (identical fixtures, documented expected values, an unchanged path to the
analysis, identical results from the analysis that exists today). The remaining part is inherited:

- **ANL-001** MUST run its FFT over every sine and sweep fixture twice and assert identical outputs,
  and assert the peak at the catalog's documented bin for each size it supports.
- **ANL-002** and **ANL-004** MUST do the same for their band and onset outputs (onsets at the
  catalog's onset indices within one analysis hop).
- **ANL-005** MUST run its beat tracker over every pulse fixture twice and assert identical beat
  times, and convergence to the catalog's tempo within its own stated tolerance.
- **ANL-016** MUST timestamp events from fixtures by frame index, so that repeated runs give identical
  event logs.
- **QA-001** extends this catalog (new fixture kinds such as seeded noise) by raising its version
  and adding golden hashes; it never changes an existing fixture's samples under the same version.

## Assumptions

- The loop length of 10 seconds keeps each signal's memory under 4 MB (stereo, 48 kHz, 32-bit) and is
  long enough for a 20-beat pulse loop and a readable sweep.
- Signals play at 48 kHz (AUD-016-R23), the usual output rate of the test devices; when the output rate differs,
  iOS converts and the analysis sees the converted signal (US3 scenario 2).
- Seeded noise is not part of this row (the roadmap names sine, sweep, pulse and silence); QA-001 or
  ANL-006/ANL-012 add it.
- The bundled reference track and its generator script are unchanged; the new generator does not
  claim to reproduce the script's bytes (the script uses the platform math library).
- CaptureLab is unchanged; the Diagnostics place is in projectM-iOS.
- Device behavior (speaker, headphones, real interruptions) is checked only in the final device
  phase and tagged `{device}`.
