# Data Model: AUD-012 Source Crossfade

No persisted data. Runtime entities:

## HandoffEnvelope (AudioCore, analysis-queue owned)

| Field | Type | Rule |
|---|---|---|
| phase | `unity`, `fadingOut`, `silent`, `fadingIn` | starts `unity` |
| position | Int 0…4,410 | gain = position / 4,410; `unity` ⇔ position 4,410 and phase unity |
| lastLeft, lastRight | Float | last frame written (post-gain), for a forced fade-out |

Transitions: `unity`/`fadingIn` —beginFadeOut→ `fadingOut` (from the current position);
`fadingOut` —position reaches 0→ `silent`; `fadingOut` —completeFadeOut→ `silent` (synthesized ramp
of min(position, 1,024) frames from the last frame); `silent` —beginFadeIn→ `fadingIn`;
`fadingIn` —position reaches 4,410→ `unity`; any —reset (non-handoff session)→ `unity`.

## Renderer boundary counters (NormalizedPCMRing)

| Field | Type | Rule |
|---|---|---|
| sanitizedSampleCount | Int (atomic) | input + output replacements since creation; never reset by a session |

## HandoffTiming (CaptureKit)

| Field | Default | Rule |
|---|---|---|
| fadeOutWaitLimit | 150 ms | `.immediate` = 0 (tests) |
| pollInterval | 5 ms | |

## CaptureManager additions

| Field | Type | Rule |
|---|---|---|
| switchingTo | `AudioSourceMode?` | non-nil = "Switching source…" (label rule, contract C3) |
| sanitizedSampleCount | Int | copied from the ring on each update |
| onSessionMode | `((AudioSourceMode?) -> Void)?` | called when `activeMode` changes at a session boundary (AUD-011 flag) |
