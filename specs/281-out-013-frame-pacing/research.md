# Research: OUT-013 Frame Pacing per Output

## OUT-013-D1: Which clock paces a visual

- **Decision**: the display link of the screen that shows the visual's view: `UIWindowScene.displayLink(target:selector:)`
  on iOS 27 (behind `#if compiler(>=6.4)` + `#available(iOS 27.0, *)`, the ExternalDisplayAccessory pattern), else
  `UIScreen.displayLink(withTarget:selector:)` of the window's screen (deprecated only from iOS 27), else
  `CADisplayLink(target:selector:)` while the view has no window. Rebuilt when the view's screen changes.
- **Rationale**: today every loop uses `CADisplayLink(target:selector:)`, the main screen's link. With the visual on a
  30/50 Hz display, frames are produced at up to 60 Hz for a display that consumes fewer: drawables pile up and the
  next `nextDrawable` blocks the main thread. Pacing by the consuming screen removes that mismatch at the source.
- **Alternatives**: `CAMetalDisplayLink` (hands over drawables itself; does not fit ANGLE, which fetches its own
  drawable inside `eglSwapBuffers`' surface, and would split the six loops into two designs); a timer (no vsync).

## OUT-013-D2: Bound and release point

- **Decision**: 2 frames in flight per output; a frame leaves flight at GPU completion (Metal: the command buffer's
  completed handler, any thread, atomic release; ANGLE: a GL fence polled with a zero timeout at each tick on the main
  thread).
- **Rationale**: with three drawables, two in GPU flight plus one on screen keeps one free for the next frame in the
  normal case. `MTLDrawable.addPresentedHandler` is missing from the simulator SDK (PERF-007-D1), so completion is the
  release point that works everywhere and is testable.
- **Alternatives**: a `DispatchSemaphore` (`wait` blocks: rejected by R3); 3 in flight (lets the GPU queue a third frame
  of latency and leaves no drawable spare).

## OUT-013-D3: ANGLE's drawable wait

- **Finding**: ANGLE's `WindowSurfaceMtl::obtainNextDrawable` (Vendor/angle `SurfaceMtl.mm`) calls `nextDrawable`; when
  it returns nil it sets `allowsNextDrawableTimeout = NO` and waits **indefinitely**. ANGLE renders on the main thread
  (the renderer's display link is on the main run loop; there is no separate ANGLE render thread).
- **Decision**: no ANGLE patch. The gate keeps ANGLE from starting a frame while two are in flight, and D1 paces it by
  the consuming display, so the drawable fetch finds a free drawable in the normal case. Residual: if the display stops
  returning drawables altogether (an adapter hang), ANGLE's own wait can still block; OUT-002 removes the slot on
  disconnect. Recorded in the contract.
- **Alternatives**: move ANGLE to its own thread (engine, flash limiter, capture and health all assume the main thread;
  out of scope for P2/L); patch ANGLE (Constitution VIII: upstream-ready only; not needed for the bound).

## OUT-013-D4: Slow drawable wait back-off

- **Decision**: Metal hosts time `nextDrawable()` with the host clock (`CACurrentMediaTime`); a wait longer than half the
  link's refresh interval arms a one-tick back-off: the next tick is dropped (counted). `nextDrawable()` returning nil is
  a drop (counted) and the slot is returned.
- **Rationale**: a wait means the display holds the drawables; giving it one tick lets it catch up without any queue.
  The layer's `allowsNextDrawableTimeout` stays on (1 s cap), `maximumDrawableCount` 3, set explicitly (R6).

## OUT-013-D5: Testing without the wall clock

- **Decision**: FrameTimingTests run a discrete-event simulation of one main thread: device ticks every 1/120 s, the
  output's link every 1/60 s, an output that completes each frame 100 ms after submission, 1 ms of encode work per
  rendered frame. The gate is the real `OutputFrameGate`; a control policy that waits for a free slot shows the model can
  fail (up to ~100 ms late). App and ANGLE tests hold completions/fences instead of delaying them, and the app probe
  check uses a loose real-time bound (no tick gap > 0.25 s) only as a smoke check; its hard assertions are counts.
