# Contract: Source handoff (AUD-012)

## C1. Renderer boundary (`NormalizedPCMRing.write`, AudioCore)

1. Every sample written to projectM's ring and the analysis tap is finite and in [−2, 2]: the
   capture path's ring (`AudioAnalyzer.normalizedOutput`) is made with `sampleBound` 2. A ring made
   without a bound (harnesses, RendererLab) replaces only NaN/±Inf.
2. A write whose samples are all finite and in range, with the envelope at unity, writes the
   caller's samples unchanged (bit-identical) and makes no copy.
3. Otherwise the write is processed in chunks of ≤ 1,024 frames through a preallocated scratch:
   NaN/±Inf → 0, x > 2 → 2, x < −2 → −2 (each counted), then the envelope gain is applied per frame.
4. No allocation, lock or logging; producer side only (the analysis queue).
5. `reset()` (a new non-handoff session) sets the envelope to unity (unchanged ANL-016 behavior).
6. `resetForHandoff(silenceFrames:)`: empties the tap and restarts its counters, keeps projectM's
   ring, advances the generation after the drain, writes `silenceFrames` zero frames to both rings,
   and leaves the envelope silent so the next `beginFadeIn()` ramps from 0.
7. `beginFadeOut()`, `completeFadeOut()`, `beginFadeIn()`, `handoffPhase`: producer side only
   (the analyzer calls them inside its queue).

## C2. `CaptureManager.switchSource(to:)` (CaptureKit)

1. Same mode as `activeMode` with a running or starting session: no effect.
2. Synchronously: `switchingTo = mode`, then cancels a pending start (FR-052, as `select`).
3. Serialized: if a source is current and running, start the fade-out and wait (≤ `fadeOutWaitLimit`,
   skipped when not running), complete it; then stop the old source (FR-016) and run a handoff
   attempt (C1.6, fade-in armed); then start the new source as `select` does.
4. A newer command (switch, select, stop, restart) supersedes: the old wait ends at once, the
   envelope continues from its current position (no jump).
5. `stop()` during a switch clears `switchingTo` synchronously and ends as Stop always does.
6. `select`, `stop`, `restart`, `resume`, `pause` keep their behavior (no fade, no label change).

## C3. Label rule

`switchingTo` is non-nil from the request until the first of: an update of the new attempt with
`statistics.sampleCount > 0` and a running state; a state other than Waiting/Not started in the new
attempt; the attempt ends (`startFailed`, `failed`, `endedBySystem`, `userStopped`) while no newer
command is pending; `stop()`. While non-nil the app shows "Switching source…" in the indicator,
its accessibility label and announcements, and hides the AUD-007 route indicator.

## C4. Generation rule

At the switch point the tap is emptied, then the generation advances; the old source is already
stopped and the drain timer off, so no old-session frame can be written to the tap afterwards.
Consumers (`NoiseGateReader`, `InputTrimReader`, `AnalysisPipeline`) reset or drop on the change
as they already do (ANL-016-R9, AUD-011-R9).

## C5. App (`AppCoordinator.switchSource(to:)`)

1. Only on the visualizer, only for an available mode other than the current one.
2. Microphone with a pending explainer → `stop()` and `select(.microphone)` (the chooser shows the
   explainer, FR-005).
3. In-App Playback → the reference track (as the chooser row), then the manager's switch.
4. The visual is neither paused nor recreated; `sourceStarts` counts the switch.
5. AUD-011's microphone flag is set by the manager's session callback at the switch point.
