# ADR-0032: Crash Recovery Never Reopens Sensors or the Network Without Consent

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: PERF-010 (`specs/070-perf-010-crash-safe-session-recovery`)
- **Constitution**: I (public APIs only), X (evidence); Privacy (capture and listening start only
  after explicit user action)
- **Builds on**: ADR-0008 (owner ruling on OSC networking: off until the user enables it), ADR-0017
  (camera, session only), ADR-0028 and its SCN-002 amendment (scene autosave and launch restore)
- **Overrides**: OSC-001-R15 (the OSC toggle is persisted and reopens the listener at launch) after an
  abnormal exit only
- **Number**: 0031 is left to SHOW-001, which runs in parallel and may claim it.

## Context

The roadmap row PERF-010 asks the app to "offer reopening last locally saved scene after abnormal
exit", accepted when a "simulated crash never reopens camera or network listener without consent".
The audit (spec Baseline) found that every launch is handled alike: SCN-002 restores the committed
scene silently, and OSC-001's persisted toggle reopens the local-network listener at launch, already
on the source chooser, whether the previous session ended cleanly or not. The camera is session only
(CAM-001-R11) and never restarts by itself.

## Decision

1. **Abnormal-exit detection**: a "session open" flag in the app's UserDefaults, set at launch and on
   a return to the foreground, cleared on the background transition and on terminate. A launch that
   finds it set follows an abnormal exit. No timestamps, crash reporters, signal handlers, MetricKit
   or private API. A crash while in the background is not detected (accepted limitation; a kill by
   the system in the background is a normal end on iOS).
2. **OSC after an abnormal exit**: the stored toggle `settings.osc.enabled` is turned off before the
   receiver is created, so no listener opens, and only the user turning it on again opens it. A
   one-shot suspension was rejected: it would leave the stored value on and the next normal launch
   would reopen the listener without new consent. The port is kept. After a normal exit OSC-001-R15
   is unchanged.
3. **Scene after an abnormal exit**: SCN-002's restore is held, not applied. The app shows the fresh
   scene (scene settings at their defaults) and a non-blocking card offers **Reopen last scene** or
   **Start fresh**. Reopen applies the committed scene and the visual stored at the exit (never
   Camera); Start fresh commits the fresh scene. An unanswered offer is shown again on the next launch.
4. **Crash-loop guard**: an abnormal exit in the session where the user tapped Reopen, or in the next
   one (N = 2), offers Start fresh only and commits the fresh scene at once.
5. **Harness**: DEBUG and automation launches (UI tests, the unit-test host, `PROJECTM_AUTORUN`) are
   treated as clean unless a test passes `-uitestSessionRecovery`, because they relaunch without a
   background transition. Release builds always decide.

## Consequences

- A crash can never turn the network listener or the camera back on; the user re-enables OSC in
  Settings (one tap) after a crash.
- A user who relied on OSC being on at every launch must turn it on again after a crash; the card
  says "OSC was turned off".
- The privacy policy lists the three stored values and the rule.
- Device evidence is PERF-010-T15 (`{device}`, D1): a real crash with the DEBUG "Crash now" button.
