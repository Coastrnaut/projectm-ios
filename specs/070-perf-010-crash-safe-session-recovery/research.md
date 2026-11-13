# Research: PERF-010 Crash-Safe Session Recovery

## PERF-010-D1 Detecting an abnormal exit

- **Decision**: A Bool `session.recovery.open` in the app's UserDefaults: set true at launch (after
  the decision is taken) and on `willEnterForegroundNotification`; set false on
  `didEnterBackgroundNotification` and `willTerminateNotification`. Found true at launch → abnormal.
  Each write is followed by nothing else (UserDefaults persists asynchronously; the background write
  happens while the app still runs, and a kill after it is a clean exit).
- **Rationale**: Public, immediate at launch, no timestamps (no required-reason file timestamp API;
  UserDefaults is already declared in the privacy manifest), no network.
- **Alternatives**: MetricKit `MXCrashDiagnostic` (arrives on a later launch, cannot drive the launch
  decision; rejected, not used even for diagnostics to keep the manifest unchanged); signal/exception
  handlers (unsafe in Swift, not allowed for privacy and reliability); a marker file (same semantics
  as the flag, more code).
- **Limitation**: a crash while in the background is not detected; a kill by the system in the
  background is (correctly) a clean exit.

## PERF-010-D2 OSC after an abnormal exit

- **Decision**: Before `OSCReceiverCoordinator` is created, an abnormal launch sets
  `settings.oscEnabled = false` (writes the stored toggle). The receiver therefore never starts. The
  offer card says "OSC was turned off." when it had been on.
- **Rationale**: A one-shot suspension would leave the stored value on and reopen the listener on the
  next normal launch without consent. Clearing is the conservative reading of ADR-0008's ruling.
- **Alternatives**: suspended state shown as "Paused" (rejected above); asking "Turn OSC back on?" in
  the card (a consent prompt mixed with the scene offer; the Settings toggle already is the consent).

## PERF-010-D3 Offer vs silent restore

- **Decision**: Offer. While unanswered, the scene settings (visual, bars, orientation, spacing, glow
  on/intensity/radius/threshold) are at their defaults and SCN-002's restored values are held in
  memory. Reopen applies the held values (`SceneAutosaveCapture.apply`, text) and the held visual.
- **Held visual**: SCN-002's restore does not carry the visual (the stored setting does), so the
  visual stored at launch is copied to `session.recovery.heldVisual` before the defaults are applied;
  a later abnormal launch with an unanswered offer reuses it (R8). Camera is never held (the stored
  visual is never Camera; `recordedVisual` maps it anyway).
- **Start fresh**: dismisses, clears the held visual and commits the fresh scene at once
  (`commitFreshScene`), so a later normal launch does not silently restore the held scene (SCN-002
  keeps the previous file as its backup). A crash loop commits the fresh scene at launch.
- **Held scene**: on an abnormal launch SCN-002's coordinator reads the committed scene without
  adopting it (`holdCommittedScene`: load only; the carry stays fresh, so a native spectrum created
  while the offer is pending gets no restored bindings). Reopen adopts the held document
  (`reopen(held)`: carry, restored source, values). If the user edits while the offer is pending, the
  next commit replaces the file with the fresh scene; the held copy in memory still reopens in this
  session, but a second kill after such an edit offers the newer file instead (spec Edge Cases).

## PERF-010-D4 Crash-loop guard

- **Decision**: `session.recovery.sessionsSinceReopen` (Int, absent when not recent). Reopen sets 0.
  At each launch: `previous = stored`; abnormal and previous < 2 → crash loop (Start fresh only,
  counter removed); otherwise counter = previous + 1, removed when it reaches 2.

## PERF-010-D5 Test harness

- **Decision**: DEBUG builds treat a launch as clean (decision `.suppressed`, marker still written)
  when any argument starts with `-uitest` or is `-autostart`, `XCTestConfigurationFilePath` is set
  (unit-test host), or `PROJECTM_AUTORUN` is set — unless `-uitestSessionRecovery` is passed.
  `-uitestResetNotice` removes the three keys. Release builds always decide. Recorded so other suites
  are unaffected.

## PERF-010-D6 Diagnostics

- **Decision**: `DiagnosticsLog.app.notice` once per abnormal launch with public flags only
  (`crashLoop`, `sceneAvailable`, `oscTurnedOff`); the coordinator keeps the decision for the DEBUG
  probe. No user data.

## PERF-010-D7 What else could restart by itself (audit)

Audio source, camera, external display, recording, blackout: none restart by themselves (spec
Baseline). Only OSC needed a change.
