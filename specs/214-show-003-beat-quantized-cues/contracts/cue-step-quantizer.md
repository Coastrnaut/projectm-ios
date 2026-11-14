# Contract: Cue step quantizer (SHOW-003)

## Q1 — `QuantizedCueStep` (PerformanceControl)

- `request(_ r: CueStepRequest, at t: UInt64, tempo: TempoSnapshot, timed: Bool = false) -> CueStepRequestResult`
  - Off → `.applyNow(.off)`; Beat/Bar with `tempo.nextBoundary(after: t, beats: 1|4) == nil` → `.applyNow(.noTempo)`
    (a pending step is dropped).
  - Empty slot → `.queued(deadline)`; same request pending → `.cancelled` (manual) / `.kept` (timed);
    different request pending → `.replaced(deadline)` (manual) / `.kept` (timed).
- `takeDue(at t) -> CueStepRequest?`: the pending request when `t >= deadline`, removed; else nil.
- `cancel() -> Bool`, `setMode(_:) -> Bool` (true when a pending step was dropped), `deadline`, `pendingRequest`.

## Q2 — App (`ShowCueQuantizer`, `ShowCoordinator`)

- `ShowCoordinator.next/previous/go(to:)`: with a quantizer in Beat/Bar mode and a tempo, a request that would move
  returns `.queued` and changes nothing now; one that would not move returns its outcome as today and queues nothing.
- At the deadline the request runs once through the step path; `appliedAtBoundary` counts it.
- `ShowCoordinator.timedNext()` (SHOW-002) is a `timed` request.
- `ShowCueQuantizer.queuedText`: "Cue queued for the next beat" / "… bar" while pending, else nil.
- Announcements (cue lane): queued text, "Queued cue cancelled", "Cue changed now, no tempo".
- Launch argument `-settings.show.quantizeCues beat|bar` sets the mode (UserDefaults argument domain) for UI tests.
