# Contract: Output Frame Pacing (OUT-013)

## C1 `OutputFrameGate` (FrameTiming)

`public final class OutputFrameGate: Sendable` with `init(policy: OutputPacingPolicy = .standard)`, `tryBegin() -> Bool`,
`complete()`, `abandon()`, `noteDrawableWait(_:refreshInterval:)`, `counts: OutputPacingCounts`. Never blocks, never
allocates after init, safe from any thread (atomics). Data model: [data-model.md](../data-model.md).

## C2 `ScreenDisplayLink` (ANGLERendering, main actor)

`init(view: UIView, target: AnyObject, selector: Selector, range: CAFrameRateRange, paused: Bool)` builds the link of the
view's current screen and adds it to the main run loop (`.common`). `preferredFrameRateRange`, `isPaused`, `invalidate()`
mirror `CADisplayLink`. `follow(_ view: UIView)` rebuilds the link when the view's screen differs from the one the link
was built for (same target, selector, range and pause state) and returns whether it did. `screenIdentity` names the
screen the link follows (tests).

## C3 projectM on ANGLE

Per tick: poll fences (zero timeout; signalled → `complete()`); PERF-014 back-off as today; `tryBegin()` or drop; render
and swap; on a presented frame insert a fence (`glFenceSync`); on a frame that did not present, `abandon()`. The view's
`didMoveToWindow` calls `follow`. The layer: `maximumDrawableCount = 3`, `allowsNextDrawableTimeout = true`.
Residual (research OUT-013-D3): ANGLE's own indefinite drawable wait remains reachable only when the display stops
returning drawables entirely.

## C4 Metal hosts (`MetalOutputPacing`, app)

`begin() -> Bool`; `nextDrawable(from:refreshInterval:)` (times the wait, abandons on nil); `track(_ commands:)` adds the
completion handler that calls `complete()`. Hosts: native spectra, camera, photo, video, text. The view's
`didMoveToWindow` calls `follow`. DEBUG: `holdCompletions` keeps completions until `releaseHeldCompletions()` (tests).
