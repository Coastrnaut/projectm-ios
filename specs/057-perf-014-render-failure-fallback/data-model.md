# Data Model: PERF-014 Render Failure Fallback

All types are plain Swift values in `Packages/Compositor/Sources/Compositor/RenderHealth.swift`
(builds on Linux), except where noted.

## RenderFaultReason (enum, String raw values)

`layerPrepareFailed`, `missingTexture`, `layerRenderFailed`, `gpuTimeout`, `gpuPageFault`,
`gpuNotPermitted`, `gpuOutOfMemory`, `gpuError`, `presetLoadFailed`, `presentationFailed`,
`visualUnavailable`. The raw value is the identifier logged and shown (no user content).

## RenderRecoveryPolicy

| Field | Default | Rule |
|---|---|---|
| firstDelayTicks | 30 | > 0 |
| maxRetries | 4 | ≥ 0 |

`delay(afterRetries n) = firstDelayTicks << n` (30, 60, 120, 240).

## RenderRetryState (one per failing part: a layer, a visual's GPU work / composite, projectM presentation)

Phases: `ok`, `waiting(retryAt)`, `retrying(since)`, `gaveUp`; `retriesUsed`.

| Event | From | To | Counted? |
|---|---|---|---|
| fault(tick) | ok | waiting(tick + delay(retriesUsed)) | yes |
| fault(tick) | retrying, retriesUsed < max | waiting(tick + delay(retriesUsed)) | yes |
| fault(tick) | retrying, retriesUsed == max | gaveUp | yes |
| fault(tick) | waiting, gaveUp | unchanged | no (coalesced) |
| beginRetry(tick) | waiting with tick ≥ retryAt | retrying(tick), retriesUsed + 1 | — |
| succeeded(encodedAt) | retrying(since), encodedAt ≥ since | ok, retriesUsed 0 | recovery |
| succeeded(encodedAt) | any other | unchanged | no |
| reset(tick) | ok | ok | — |
| reset(tick) | waiting, retrying, gaveUp | retrying(tick), retriesUsed 0 | — |

`isHolding` = waiting or gaveUp (the part must not run). `isRetryDue(tick)` = waiting and
tick ≥ retryAt. With faults at every retry, retries happen at ticks f+30, f+90, f+210, f+450 and the
part gives up at the fifth counted fault.

## RenderHealthState

`healthy`, `recovering`, `degraded`, `placeholder`. Derived (`RenderHealth.state(parts:visual:)`):
visual part gave up, or at least one layer part and all gave up → placeholder; any part gave up →
degraded; any part waiting or retrying → recovering; else healthy.

## RenderHealth (one per visual)

| Field | Meaning |
|---|---|
| state | RenderHealthState |
| faultCount | counted faults (episodes + failed retries) |
| lastReason | RenderFaultReason? |
| lastFaultTick | UInt64? (the visual's tick) |
| recoveries | successful retries |
| revision | changes on every update (observers compare it) |

`summary(visual:)` → `"<visual> <state> <lastReason|none> faults <n> recoveries <n> tick <t|->"`;
`debugValue` is the same without the visual. `recordFault(_:atTick:)` (count, reason, tick, revision),
`recordRecovery()`, `setState(_:)` (revision only when changed).

## RenderFaultInjection (DEBUG use only; the type builds everywhere)

| Field | Effect |
|---|---|
| failingPrepare: Set<String> | layers with these names fail `prepare` (`.resourceUnavailable("injected pipeline failure")`) |
| missingPictures: Set<String> | layers with these names get no picture |
| failingRender: Set<String> | layers with these names throw `.engineFailure("injected")` from render |
| gpuFault: RenderFaultReason? | finished command buffers read as errors with this reason |
| failPresetLoads: Int | the next n projectM preset loads fail ("preset load failed", invalid shader) |
| failPresentation: Bool | projectM's swap reads as failed |

`parse(_:)` reads `prepare:<name>`, `picture:<name>`, `render:<name>`, `gpu:<reason>`, `preset:<n>`,
`present`, comma-separated; unknown items are ignored.

## App (projectM-iOS)

- `RenderPlaceholder` (enum): `fadeSeconds = 0.5`, `opacity(elapsed:)`, `note = "Visual unavailable"`.
- `AppCoordinator`: `activeRenderHealth` (the shown visual's record), `renderHealthRevision`
  (observable), `visualCreationHealth` (records `visualUnavailable` for VIS-001-R16 fallbacks),
  `showsRenderPlaceholder`.
