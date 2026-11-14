# Research: SHOW-002 Timed Cue Advance

## SHOW-002-D1: Clock

- Decision: an injected `ShowMonotonicClock` protocol returning `Duration` since an arbitrary origin. The app uses `ShowContinuousClock` (`ContinuousClock`, never goes backwards, keeps counting while the device sleeps); tests use `ShowManualClock` (set or advance by hand).
- Rationale: deadlines must not move when the user changes the time of day (wall clock) and must be testable without waiting. `Duration` is integer-backed, so `start + dwell` comparisons are exact.
- Alternatives: `Date` (wall clock, rejected: time changes and NTP corrections); `SuspendingClock` (stops while asleep; not needed because the app holds the countdown in the background anyway); `CACurrentMediaTime` (QuartzCore, not on Linux).

## SHOW-002-D2: A clock jump past several deadlines

- Decision: fire once. A tick at or after the deadline advances one cue and restarts the timeline for the new cue from the tick's time. No catch-up.
- Rationale: a stall (debugger, a long frame, a held main thread) must never produce a burst of scene changes, which would be a flashing risk and skip cues the audience never saw. The roadmap acceptance asks for one advance per cue at its deadline.
- Alternatives: catch up to the cue the schedule says should be active (rejected: bursts and skipped cues); restart from the missed deadline (rejected: the next cue would be cut short by the stall).

## SHOW-002-D3: Driving the engine in the app

- Decision: a main-actor task that sleeps `min(250 ms, remaining)` and ticks, running only while the timeline is not idle; the hold state is polled on each tick (pause, blackout phase, repair report pending, app inactive) and also re-evaluated on each step.
- Rationale: one small loop, no observation plumbing into shared coordinators (AppCoordinator stays a small edit), quarter-second accuracy is invisible in a visual show, and an idle show costs nothing.
- Alternatives: a `Timer` (RunLoop, harder to test); observing each hold source (more edits in shared files).

## SHOW-002-D4: Holds

- Decision: pause (`userPaused`), blackout (`blackoutPhase != .live`), an open repair report (SCN-012 `pending`) and the app not active each hold the countdown; the remaining time is kept and resumes when no hold remains. A step while held starts the new cue held with its full dwell.
- Rationale: in each case the audience is not seeing the cue, or the performer is busy with a decision; advancing unseen would surprise them.
- Alternatives: keep counting during blackout (rejected: a cue could pass while black); reset to the full dwell after a hold (rejected: a short pause would lengthen the cue).

## SHOW-002-D5: Stored format

- Decision: an optional integer cue field `advanceAfter` (seconds), written only when set, with sorted keys as before. Invalid values (non-integer, ≤ 0, > 3600, wrong type) are dropped with `ShowDecodeWarning.droppedDwells(n)`; the rest of the show loads. No version bump (SCN-004/005/007 pattern); older builds ignore the field.
- Alternatives: fractional seconds (rejected: whole seconds are enough for the editor and make the file deterministic); a show-level default dwell (deferred; per-cue covers it).

## SHOW-002-D6: Dwell edits on the active cue

- Decision: restart the active cue's countdown from the edit with the new dwell; Off cancels.
- Rationale: predictable; avoids an instant advance when shortening a dwell that has already elapsed.
