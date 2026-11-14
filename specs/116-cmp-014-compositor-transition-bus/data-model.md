# Data Model: CMP-014 Compositor Transition Bus

## SceneTransitionStyle (enum, String raw values, Codable)

`cut`, `crossfade`, `dipToBlack`.

## SceneTransitionEasing (enum, String raw values, Codable)

`linear` (e = t), `easeInOut` (e = t²(3 − 2t)); both exact at 0 and 1 and monotonic.

## SceneTransitionSpec (struct, Sendable, Equatable, Codable)

| Field | Type | Rule |
|---|---|---|
| style | SceneTransitionStyle | — |
| durationSeconds | Double | finite, 0…10 (`maximumSeconds`); a cut has 0 |
| easing | SceneTransitionEasing | default `easeInOut` |

- `init(style:durationSeconds:easing:) throws(SceneTransitionError)` (`nonFiniteDuration`,
  `durationOutOfRange`); decoding validates the same way.
- `static let cut`, `static let defaultCrossfade` (crossfade, 1 s, ease in-out).
- `isInstant`: style is cut or duration is 0.
- `resolved(reduceMotion:)`: `.cut` when Reduce Motion is on, else self.

## SceneTransitionClock (struct, Sendable)

| Field | Meaning |
|---|---|
| durationNanoseconds | UInt64 from the spec |
| elapsedNanoseconds | summed clamped frame durations |
| previous | last presentation time (nil at start and after `pause()`) |

- `advance(presentationTimeNanoseconds:) -> Double` returns the raw progress after this frame.
- `progress` (0…1, exactly 1 when elapsed ≥ duration or duration 0), `isFinished`, `pause()`.

## SceneTransitionWeights

`(outgoing: Float, incoming: Float)` from `SceneTransitionMix.weights(style:eased:)`:
crossfade (1 − e, e); dip to black: e < 0.5 → (1 − 2e, 0), else (0, 2e − 1); cut (0, 1).

## SceneTransitionBus (class, Metal; one thread)

States: **idle** (no live scene) → **live** (one scene) ⇄ **transitioning** (outgoing + live + clock +
blend target). `show(_:)` cut; `transition(to:spec:reduceMotion:)`; `cancel()`; `finishNow()`;
`pause()`/`resume()`; `encodeFrame(into:commandBuffer:presentationTimeNanoseconds:contentScale:reduceFlashing:audio:)`;
`encodeOutput(into:commandBuffer:)`. Diagnostics: `isTransitioning`, `progress`, `blendedFrames`,
`blendTargetCheckedOut`, `lastFlashGain`.
