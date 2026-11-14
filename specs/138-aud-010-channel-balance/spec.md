# Feature Specification: AUD-010 Channel Balance

**Feature Branch**: `feature/aud-010` (spec directory `138-aud-010-channel-balance`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (device task AUD-010-T16 open)

**Input**: User description: "Implement AUD-010 (Channel balance) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md line 97. Observable behavior, verbatim: "Expose independent L/R
monitoring balance for in-app playback only." Acceptance, verbatim: "Pan test track and verify
analysis remains sourced from original PCM." P2, size S, depends on AUD-006. Verification: unit
tests plus the simulator; device testing for routes and interruptions."

Identifiers carry the roadmap ID: requirements `AUD-010-R1…`, success criteria `AUD-010-S1…`, tasks
`AUD-010-T01…`. Requirements of other features are cited by their own IDs: FR-065 (what the app may
store), FR-069 (In-App Playback never opens an input), FR-070 (accessibility), AUD-006-R10 (no stale
audio after a cut), AUD-008-R6 (analysis-only settings are user settings), AUD-014-R10 (held position
across interruptions), ACC-005 (VoiceOver parameter editing), FILE-005 (settings backup).

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c`)

The roadmap marks this row "Gap candidate; re-audit at implementation". The audit confirms the gap.

- **In-App Playback graph** (`Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackGraph.swift`,
  AUD-006): `AVAudioPlayerNode → mainMixerNode → outputNode` (the implicit connection). The analysis
  tap is installed on the **main mixer's output bus**; it writes into `PCMSink`, which feeds the
  Normalizer, projectM's ring and the analysis tap ring. What the user hears is the same main-mixer
  output, sent on to the output node. No node exists between the tap and the output, so any gain or
  pan on the existing nodes would also change the analysed PCM.
- **Analysis-only settings** (AUD-008 input trim, AUD-009 channel selection, AUD-011 noise gate) act on
  the analysis copy *after* the sink and never change what is heard. Nothing changes what is heard
  without changing the analysis; this feature is the first monitoring-only setting.
- **Sources**: Microphone and System/App Capture are not monitored by the app (FR-069; the app never
  plays captured audio back), so a monitoring balance has nothing to act on there.
- **Measured** (2026-11-14, macOS 27.2 host, offline manual rendering): an `AVAudioMixerNode` whose
  stereo input is panned with the input bus's `pan` acts as a *linear stereo balance*, not as
  mono-panning: at pan p < 0 the left channel passes at unity and the right is scaled by 1 + p
  (p = −0.5 → right × 0.5; p = −1 → right silent); the right content is not folded into the left.
  Symmetric for p > 0.

| Area | Today | Gap for this row |
|---|---|---|
| Left/right balance of what is heard | None (always centred). | A user balance, In-App Playback only. |
| Analysis PCM | Main-mixer output. | Must stay exactly the unbalanced PCM at every balance. |
| Settings | Audio Analysis, Analysis Channel, Noise gate, Visual delay sections. | One balance row for playback. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing delegation (owner rule 4); each answer is the
conservative, local-first option, recommended option first.

- Q: Balance law: AVAudioMixerNode pan or explicit per-channel gains? → A: A true balance law: the
  near channel stays at unity and the opposite channel is scaled linearly by 1 − |b| (b = −0.5 →
  right × 0.5; b = ±1 → the opposite channel silent). Content of one channel is never moved to the
  other. It is realised by a dedicated mixer node after the tap whose input-bus `pan` was measured to
  be exactly this law for stereo input (Baseline); tests pin the law at −1, −0.5, 0, 0.5 and 1, so an
  OS change to it fails a test rather than shipping silently. No custom DSP runs on the render thread.
- Q: Mono tracks? → A: The main mixer already places a mono track on both channels; the balance then
  attenuates one side the same way. No special case.
- Q: Unavailable sources: hidden or disabled? → A: Disabled, with a footer that says it applies to
  In-App Playback only. The stored value is kept and applies at the next In-App Playback session.
  Disabled (not hidden) keeps the row discoverable and matches the Noise gate's "Microphone only"
  pattern. With no active source the control is disabled too.
- Q: Range, grid and detent? → A: −1…+1 stored as a Double, rounded to whole percent; values within
  ±3% snap to 0 (the centre detent). VoiceOver swipes move by 10%. Double-tap on the slider resets to
  centre, and a "Center" button does the same for those who cannot double-tap.
- Q: Storage key and scope? → A: `settings.playbackBalance.position`, one global value (not per track,
  not in scenes or show cues). It is a user setting under FR-065 like AUD-008-R6, included in the
  FILE-005 backup and erased with Settings.
- Q: Does a balance change cut or discard audio? → A: No. It changes a mixer parameter only: no cut,
  no discard, the position and the analysis stream continue (AUD-006-R10 untouched).
- Q: Recording (REC-004, in progress elsewhere) and projectM? → A: Both read the analysis path or the
  sink; they receive the unbalanced PCM. The balance is about what the listener hears only.
- Q: Is a balance change an undo step (SCN-010) or a scene field? → A: Neither. Like AUD-008's trim it is
  a device listening preference, outside scenes, show cues and the scene history.
- Q: Is anything logged or announced when the balance changes? → A: Nothing is logged (no diagnostics
  field) and nothing is announced beyond VoiceOver reading the slider's new value; the visible readout
  ("Centered", "30% left") is the feedback.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Balance what I hear without changing the visuals (Priority: P2)

A listener playing a track in the app (In-App Playback) sits off-centre or has uneven hearing. They
open Settings, move Balance towards the left or right, and hear the opposite side get quieter. The
visuals keep reacting exactly as before, because the analysis still reads the original audio.

**Why this priority**: Comfort feature for the monitored output; P2 in the roadmap.

**Independent Test**: Play a stereo test track with a different tone in each channel through the
playback graph at balance fully left, centre and fully right; the analysed PCM is identical in all
three runs, and the heard output's channel energies follow the balance law.

**Acceptance Scenarios**:

1. **Given** In-App Playback of a stereo track, **When** the balance is fully left, **Then** the right
   channel is silent in what is heard, the left is unchanged, and the analysis receives the same PCM
   as at centre.
2. **Given** balance −0.5, **When** the track plays, **Then** the heard right channel is at half
   amplitude and the left at unity.
3. **Given** a balance change while playing, **When** it is applied, **Then** playback continues from
   the same position with no cut and no discarded analysis audio.

---

### User Story 2 - Set, reset and keep the balance (Priority: P2)

The user finds Balance in Settings, sets it, double-taps the slider (or taps Center) to return to
centre, and finds their value again after relaunch. VoiceOver reads "Balance, centered" or
"Balance, 30 percent left" and swipes move it in 10% steps.

**Independent Test**: Settings unit tests (validation, detent, persistence, text) and a UI test that
moves the slider and resets it.

**Acceptance Scenarios**:

1. **Given** a stored balance of −0.3, **When** the app relaunches, **Then** the slider shows
   "30% left" and playback is balanced −0.3.
2. **Given** balance 0.02, **When** stored, **Then** it is 0 (detent).
3. **Given** any balance, **When** the slider is double-tapped or Center is tapped, **Then** it is 0.

---

### User Story 3 - No balance for sources the app does not play (Priority: P2)

With the Microphone or System/App Capture active, the Balance row is disabled and says it applies to
In-App Playback only.

**Independent Test**: The availability rule (active mode → enabled) unit-tested for all three modes
and none; the UI test checks the row is disabled for a non-playback source.

**Acceptance Scenarios**:

1. **Given** the Microphone source, **When** Settings opens, **Then** the Balance slider is disabled.
2. **Given** In-App Playback, **When** Settings opens, **Then** it is enabled.

### Edge Cases

- Stored value missing, NaN, not a number or out of range → 0 or clamped.
- A mono track: both channels carry it; balance attenuates one side.
- A media-services reset rebuilds the graph: the balance is applied to the new graph.
- Interruptions, route changes and hardware changes: the balance node stays in the graph; behaviour on
  real routes is a device check (left open).
- A mono output route (one speaker): the balance still acts on the stereo mix before the system
  down-mix; no claim is made about what a mono route plays.

## Requirements *(mandatory)*

### Functional Requirements

- **AUD-010-R1**: The app MUST offer a monitoring balance b in −1…+1 (−1 full left, 0 centre, +1 full
  right) for In-App Playback.
- **AUD-010-R2**: The balance law MUST be: left gain = min(1, 1 − b), right gain = min(1, 1 + b); the
  content of one channel is never mixed into the other.
- **AUD-010-R3**: The balance MUST change only the monitored output. The PCM delivered to the PCM sink
  (and so to the analysis, projectM and anything reading the sink) MUST be identical at every balance.
- **AUD-010-R4**: A balance change MUST take effect while playing without a cut, a discard or a
  position change.
- **AUD-010-R5**: The balance MUST apply to every In-App Playback track (reference, library, tones) and
  survive track changes, seeks, pauses and graph rebuilds.
- **AUD-010-R6**: The control MUST be disabled unless the active source is In-App Playback; the footer
  states it applies to In-App Playback only and does not change the visuals or recordings.
- **AUD-010-R7**: The value MUST be stored under `settings.playbackBalance.position`; missing or
  invalid values read as 0, out-of-range values are clamped, values are rounded to whole percent and
  values within ±0.03 are stored as 0.
- **AUD-010-R8**: The slider MUST use the ACC-005 accessible parameter (label "Balance", spoken value
  "centered", "30 percent left", "30 percent right", 10% swipe steps); a double-tap on the slider and
  a "Center" button reset to 0.
- **AUD-010-R9**: The key MUST be listed in the device privacy allow-list, the FILE-005 included keys
  and the UI-test reset.

### Key Entities

- **Playback balance**: one global Double, −1…+1, default 0; not part of scenes.

## Success Criteria *(mandatory)*

- **AUD-010-S1**: At balance −1, 0 and +1 the analysed PCM of a stereo test track is equal sample for
  sample (within 1e-6) to the centre run.
- **AUD-010-S2**: The heard output's channel levels at −1, −0.5, 0, 0.5 and 1 match the law in R2
  within 1%.
- **AUD-010-S3**: The control is enabled for In-App Playback only (4 cases: three modes and none).
- **AUD-010-S4**: The stored value survives relaunch and invalid values never reach playback.

## Assumptions

- AUD-006's graph and offline rendering are the test bed; real routes, Bluetooth and interruptions are
  checked on a device later (`{device}` task left open).
- The system's own accessibility balance (Settings → Accessibility) stays independent and applies on
  top.
