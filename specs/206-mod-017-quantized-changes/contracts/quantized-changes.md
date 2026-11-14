# Contract: Quantized parameter changes (MOD-017)

## Q1 Package (`PerformanceControl`)

- `TempoSnapshot.nextBoundary(after time: UInt64, beats: UInt64) -> UInt64?` — the first grid point
  `anchor + k·beats·period` strictly greater than `time` (k any integer); nil without period or anchor or for
  `beats == 0`.
- `QuantizedChangeQueue<Key: Hashable & Sendable, Value: Equatable & Sendable>`:
  - `init(mode: QuantizeMode = .off, beatsPerBar: UInt64 = 4)`; `mode`; `entries` (request order);
    `pendingValue(for:)`; `boundary(for:)`; `nextDeadline`; `isEmpty`.
  - `mutating request(_ key:, value:, current:, at:, tempo:, hasCues:) -> QuantizeRequestResult` (rules in
    data-model.md; `off` → `.applyNow(.off)`).
  - `mutating takeDue(at:) -> [QueuedChange]` — removes and returns every timed entry with deadline ≤ time, in
    request order.
  - `mutating cueStepped() -> (apply: [QueuedChange], dropped: Int)` — Cue mode: all entries to apply; Beat/Bar:
    all entries dropped.
  - `mutating setMode(_:) -> Int` and `mutating clear() -> Int` — the number dropped.

## Q2 App

- `ParameterQuantizer` (main actor, observable): `mode` (persisted; a change clears and announces
  "Queued changes cleared" when it dropped any), `request(id:value:current:name:apply:)`, `tick(at:)`,
  `cueApplied()`, `queuedText(for:)` ("Queued for the next beat", "… bar", "… cue"), `isQueued(_:)`.
- Announcements (`.parameter` lane): "<Name> queued for the next beat"; "<Name> <value>, applied" at the boundary;
  "<Name> <value>, applied now, no tempo" / "…, no cues" for the fallback; "Queued changes cleared".
- `ParameterInspectorTargets.quantizedTarget(for:settings:)`: identical to `target(for:settings:)` for continuous
  parameters; for discrete ones `get` returns the pending value or the current one and `set` goes through the
  quantizer (a locked scene refuses at once, SCN-015).
- Accessibility identifiers: `quantize.mode` (Settings picker), `quantize.queued.<parameter id>` (indication).
