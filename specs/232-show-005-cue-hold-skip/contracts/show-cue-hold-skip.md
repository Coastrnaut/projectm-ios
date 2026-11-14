# Contract: cue hold and skip

- **H1 (hold)**: While Hold is on, `tick()` never calls `timedNext()`, at the deadline or any time after; the countdown shows the kept remaining time with ", held".
- **H2 (manual)**: While Hold is on, `next()`, `previous()` and `go(to:)` move exactly as without Hold; the new cue's countdown starts held with its full dwell.
- **H3 (release)**: Hold off at time t with r remaining: the advance is due at t + r (not before).
- **H4 (quantized)**: Hold on while a timed step waits for the beat withdraws it and re-arms the countdown held at 0; Hold off requests it again at once. A waiting manual step is untouched.
- **H5 (state)**: Hold is never stored, starts off, and is allowed while the scene is locked; toggling announces on the cue lane.
- **K1 (write)**: A skipped cue writes `"skip":true`; a cue not skipped writes no key. A show without skipped cues is byte-identical to the output before SHOW-005.
- **K2 (read)**: Absent, null or false → not skipped; true → skipped; any other JSON type → dropped, counted in `droppedSkipFlags(n)`; the show loads.
- **K3 (step)**: Next and Previous (all sources, timed and quantized included) land on the nearest cue that is not skipped; Go to Cue reaches any cue; every cue skipped → `.allSkipped`, no move, notice "All cues are skipped.".
- **K4 (edit)**: `ShowCoordinator.setSkipped` is refused while locked, otherwise saves at once, applies nothing, never moves the position, and cancels a countdown left without a next cue.
