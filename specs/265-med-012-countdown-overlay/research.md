# Research: MED-012 Countdown Overlay

## MED-012-D1: Time base
- Decision: an injected `MonotonicClock` giving seconds; the app's reads Swift's `ContinuousClock`
  (keeps counting while the device sleeps) relative to an origin taken at launch.
- Rationale: wall time jumps with clock and time-zone changes; SHOW-002 and SHOW-007 already use
  monotonic time. `ContinuousClock` is in the Swift standard library on every platform (Linux too).
- Alternatives: `SuspendingClock` / `systemUptime` (pauses while asleep, so a countdown would fall
  behind real time); `Date()` (wall time; rejected).

## MED-012-D2: Display rounding
- Decision: remaining seconds rounded up (`ceil`), "mm:ss" below 3,600 s, "h:mm:ss" from it.
- Rationale: the conventional countdown face: the full duration shows at the start and "00:00" only
  when it has truly finished, so the finished event and the "00:00" frame coincide.
- Alternatives: rounding down (shows "04:59" at the start and "00:00" one second early).

## MED-012-D3: Finished exactly once
- Decision: `CountdownTimer.advance(at:)` sets `hasFinished` and stops when remaining reaches 0 and
  returns true only on that transition; Reset and a new Start clear it.
- Rationale: one state flag, independent of how many updates happen or how far past zero they land.

## MED-012-D4: Ticking
- Decision: one main-actor task while running: sleep until the next change of the shown second
  (`CountdownSchedule.delay`), then tick; it ends at zero, on Pause and on Reset. No task while
  stopped. A foreground return ticks once (catches a background finish).
- Rationale: the string changes at most once a second; MED-011's tick pattern.

## MED-012-D5: Sharing with MED-011
- Decision: generalise rather than copy: `ChangedText` (change-only string), `StoredOverlayDecodeResult`
  (versioned stored value), `OverlayTextLayers` and `Compositor.attachOverlay(_:kind:)` in the app.
- Rationale: brief and Constitution VI; the clock keeps its behaviour and tests.

## MED-012-D6: Scene and cue trigger
- Decision: optional top-level scene field `countdown: {"durationSeconds": N}`; a show cue applying
  the scene restarts the countdown with N. Written into new cue scenes while "Start From New Cues"
  is on. Malformed → absent, kept verbatim (SCN-001 `extra`); no version change.
- Rationale: the minimal path: cues already apply scenes; MED-006/007/010 add optional fields the
  same way. A per-cue property would need a show-format change and a cue editor row.
- Alternatives: a cue property in the show document (format change, more UI); a scene asset
  (assets are media references).

## MED-012-D7: At zero
- Decision: hold "00:00"; announce "Countdown finished" once through `AccessibilityAnnouncer` on a
  new `.countdown` lane. No flashing (flash-safety conservative choice).
