# Contract: what every audio source guarantees (QA-007)

Extends [specs/001 contracts/audio-source.md](../../001-ios-projectm-visualizer/contracts/audio-source.md)
(guarantees 1 to 5 stay in force). Checked by `AudioSourceContractTests` for every source
configuration: System/App Capture, Microphone, In-App Playback (reference track, imported file,
test signal). "Backend" is the platform seam under the adapter (`StreamDriver`,
`MicrophoneBackend`, `InAppPlaybackBackend`); "session" is one backend start until its stop.

## Invariants

| ID | Given | When | Then |
|---|---|---|---|
| QA-007-R1 | no session | the source is selected and its start is allowed | Waiting; exactly one backend session; `activeMode` is the source's mode; In-App Playback plays the selected track |
| QA-007-R2 | a started source | the manager selects it again / the adapter's `start` is called again | never two live backend sessions: manager = one stop then one start (restart); adapter = backend stopped and the first event stream finished before the new session starts |
| QA-007-R3 | a session (or none) | stop, twice | Stopped with no reason; the backend session ended exactly once, before stop returns; the manager's stop with no session reaches no source (adapter: P7); a stop while a start waits (picker, permission prompt; P8) ends the attempt as "Not started — cancelled" |
| QA-007-R4 | a stopped session | the OS delivers an event late | the session's event stream has finished and delivers nothing; the manager's state is unchanged |
| QA-007-R5 | the source's start is denied or blocked (per-source reason P1) | the source is selected | Not started with that reason; no backend session; 0 samples; no verified audio; not current; then, allowed again, a restart reaches Waiting |
| QA-007-R6 | a started session | nothing / silent / non-silent samples arrive | "No audio received" after 5 s; "Audio received — silent", never Active, for silent samples; Active only after ≥ 250 ms of non-silent samples of this session |
| QA-007-R7 | a session that was Active | restart, switch, or start after a terminal state | Waiting, no verified audio, zero statistics, no reason |
| QA-007-R8 | any scenario | — | every recorded transition is an edge of the graph below |
| QA-007-R9 | a running session | interruption began; ended with / without resume | the outcome `InterruptionPolicy.decide` gives for the source (P2): Interrupted; one backend resume and Waiting when allowed; none otherwise; one-tap resume continues |
| QA-007-R10 | a running session / no session | background, lock, foreground, unlock | per P3: paused (one backend pause) and resumed (one backend resume, Waiting), or unchanged; with no session no backend call |
| QA-007-R11 | a running session | the source's terminal OS event (P4) | its terminal state and reason; backend stopped once; no current source |
| QA-007-R12 | any terminal outcome (Stopped, Ended by system, failed, denied) | restart | the same source starts a new session (Waiting) |
| QA-007-R13 | source A running, B ≠ A | select B | A's backend stopped before B's backend starts; one live session; `activeMode` B; Waiting with a clean slate; A's late events change nothing; A is not current |
| QA-007-R14 | an adapter or manager no longer referenced | its backend still calls an event callback | the object is released; the callback is harmless |

"Active audio" (R6) is the only state that may be described as receiving audio (Constitution IV).

## Allowed transitions (R8)

From `specs/001-ios-projectm-visualizer/data-model.md`, "Transitions". The manager's per-attempt
log starts after Not started; a new attempt starts a new log.

| From | Allowed next states |
|---|---|
| notStarted | waiting, notStarted (a failed start is always recorded) |
| waiting | noAudioReceived, silent, active, paused, interrupted, stopped, endedBySystem |
| noAudioReceived | silent, active, paused, interrupted, stopped, endedBySystem |
| silent | active, noAudioReceived, paused, interrupted, stopped, endedBySystem |
| active | silent, noAudioReceived, paused, interrupted, stopped, endedBySystem |
| paused | waiting, stopped, endedBySystem |
| interrupted | waiting, paused, stopped, endedBySystem |
| stopped | — (terminal for the attempt) |
| endedBySystem | — (terminal for the attempt) |

## Per-source parameters (documented differences, never skips)

| # | Parameter | System/App Capture | Microphone | In-App Playback (all tracks) | Citation |
|---|---|---|---|---|---|
| P1 | denied or blocked start and its reason | user declines screen recording → `screenRecordingNotAllowed`; picker cancelled → `cancelled` | permission denied → `permissionDenied` | no permission exists (FR-069); the track cannot be played → `inAppPlaybackFailed` | FR-005, FR-015, owner ruling 2026-11-08 (-3801); FR-006, AUD-001-R19 |
| P2 | interruption | not governed: began and ended change nothing (`InterruptionPolicy` rule 1) | began → Interrupted; ended with resume → resume (rule 7); without → stays Interrupted (rule 5) | began → Interrupted; ended with resume → resume (rule 14); without → stays Interrupted (rule 12) | FR-051, ADR-0001, AUD-014-R1 to R9 |
| P3 | background / lock | continues; never paused or stopped by the app | paused; foreground/unlock resumes | paused; foreground/unlock resumes | data-model lifecycle matrix, FR-050, FR-054, ADR-0001 ruling 17 (RI-003) |
| P4 | terminal OS event | `endedBySystem` → Ended by system (reason endedBySystem) | `failed(microphoneUnavailable)` → Stopped (reason microphoneUnavailable) | `failed(inAppPlaybackFailed)` → Stopped (reason inAppPlaybackFailed) | US6-AS3, data-model lifecycle matrix, FR-015 |
| P5 | return to the foreground while an interruption is still open | n/a (P2) | resumes (FR-050), as before AUD-014 | stays on hold until iOS indicates a resume (AUD-014-R5, R6) | AUD-014-R9; finding in spec Clarifications |
| P6 | resume re-checks permission | n/a | yes: revoked → Stopped, `permissionDenied` | n/a | FR-053 |
| P7 | adapter `stop()` with no session | forwarded to the driver (idempotent; must reach a start still waiting on the picker) | no backend call | no backend call | `StreamDriver.stop` docs, ADR-0001 ruling 7, `ScreenCaptureSourceTests.testStopIsIdempotent` |
| P8 | stop while the start waits | the picker is dismissed; the start throws `cancelled` | the permission prompt cannot be dismissed by the app (modal); the attempt ends as cancelled when the user answers, and a granted start is stopped again | the start never waits | contracts/audio-source.md guarantee 3; spec finding QA-007-F2 |

## Conformance harness (what a source supplies to the suite)

Each source configuration provides: its real adapter over a scripted backend; how to allow or deny
its start; how to deliver silent or non-silent samples into the live session's sink; how to send
an event through the live session's callback and, after stop, through a callback kept from the
ended session (a late OS callback); how to end the session from the OS; counters of backend
starts, stops, pauses and resumes and of live sessions; and its parameters P1 to P8.
