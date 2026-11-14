# Data Model: MOD-017 Quantized Parameter Changes

- **QuantizeMode** (`off`, `beat`, `bar`, `cue`): raw value stored under `settings.modulation.quantize`; absent or
  unknown → `off`.
- **QuantizeBoundary**: `.time(UInt64)` (monotonic ns, Beat/Bar) or `.nextCue`.
- **QueuedChange<Key, Value>**: `key`, `value`, `requestedAt` (ns), `boundary`, `sequence` (request order).
  Invariant: at most one per key; a new request for the key replaces it (new value, new boundary, new sequence).
- **QuantizeRequestResult**: `.applyNow(QuantizeImmediateReason)` (`off`, `noTempo`, `noCue`), `.queued(QuantizeBoundary)`,
  `.cancelled` (request equal to the current value removed a queued entry), `.unchanged` (equal value, nothing queued).
- **Transitions**: request → queued → (boundary) applied and removed | (newer request) replaced | (equal value)
  cancelled | (mode change, Beat/Bar scene change) cleared.
