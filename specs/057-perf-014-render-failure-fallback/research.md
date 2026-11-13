# Research: PERF-014 Render Failure Fallback

Decisions taken under owner rule 4 (best judgement); each names the rejected alternatives.

## PERF-014-D1: Back-off counts the visual's frame ticks, not the compositor's frame index

- **Decision**: The compositor counts `frameTicks`: every `composite` call with a usable output (size
  and format), including calls that cannot encode (no composite texture) and calls during a GPU
  back-off. Retry frames are computed from ticks. projectM counts display-link ticks the same way.
- **Rationale**: The frame clock's index advances only for composited frames; a visual whose composite
  texture cannot be created would never reach its retry frame. Ticks advance whenever the frame loop
  runs, stop while it is paused (the spec's edge case) and need no wall clock.
- **Alternatives**: the clock's `frameIndex` (stalls on a missing composite); wall time (untestable,
  counts while paused).

## PERF-014-D2: GPU errors are read by polling finished command buffers, not by completion handlers

- **Decision**: The compositor keeps the last three command buffers it encoded with their tick in a
  fixed ring (preallocated, main thread only). At the start of each `composite` it reads the `status`
  of each: `.completed` → success for that tick, `.error` → a fault whose reason comes from
  `MTLCommandBufferError.Code` (`.timeout` → GPU timeout, `.pageFault` → page fault, `.notPermitted` →
  not permitted, `.outOfMemory` → out of memory, anything else → GPU error); other states are left
  for a later frame. A buffer still unfinished when its slot is needed is dropped unobserved.
- **Rationale**: `addCompletedHandler` allocates a closure context per frame and runs on Metal's
  thread, needing a lock or a hop to report; polling `status` is allocation-free, lock-free and never
  waits (R7, R12, CMP-001-R9). Three slots match the drawables in flight.
- **Alternatives**: completion handlers with an atomic (per-frame closure allocation); `waitUntilCompleted`
  (blocks the main thread).

## PERF-014-D3: During a GPU back-off the compositor draws the empty composite

- **Decision**: While the visual-level retry state waits (GPU fault or missing composite), layers are
  not rendered; the over pass clears to transparent and the output pass writes black through the flash
  guard. With no composite texture, nothing is encoded (`composite` returns false).
- **Rationale**: Submitting the same layer work that just failed would reproduce the fault every frame;
  black through the flash guard is the calm placeholder picture (Clarifications Q2) and costs two tiny
  passes.
- **Alternatives**: encode nothing (the screen freezes on a possibly bright frame); keep rendering
  layers (a tight retry loop).

## PERF-014-D4: Routine layer errors are not faults

- **Decision**: `LayerSourceError.notReady` and `.frameSkipped` thrown from `render` keep CMP-001's
  per-frame behaviour (the layer is asked again next frame) and are not counted.
  `.resourceUnavailable`, `.engineFailure` and `.unsupportedPicture` from `render` are faults: the
  layer is held for its back-off. Every `prepare` failure is a fault ("layer prepare failed"); a picture
  that cannot be created is "missing texture".
- **Rationale**: Photo, Video and Camera layers throw `notReady` while loading or before the first
  camera frame; counting those would raise false faults and hold the layer.

## PERF-014-D5: Fault injection is a value on the compositor and the renderer, compiled only in DEBUG

- **Decision**: `RenderFaultInjection` (plain Swift, all hosts) lists armed faults: prepare failure,
  missing picture or render failure by layer name; a GPU fault reason; the number of next preset
  loads to fail; failing presentation. `Compositor.faultInjection` and `ANGLERenderer.faultInjection`
  exist only under `#if DEBUG` and act at the existing check points (prepare throws
  `.resourceUnavailable("injected …")`, picture creation returns nothing, render throws
  `.engineFailure("injected")`, a finished buffer reads as an error with the armed reason, the preset
  load throws a `PMEngineErrorDomain` "preset load failed" error, the swap result reads as failed).
  The app parses `-uitestRenderFaults <list>` (DEBUG) and arms new visuals from it.
- **Rationale**: SHD-011 forbids adding a faulty shader; making creation or the result check fail
  exercises the real recovery path. Release builds carry none of it (R15).
- **Alternatives**: a fault-injection shader (forbidden); a protocol-wrapped Metal device (large,
  touches every layer).

## PERF-014-D6: Health record and state rules

- **Decision**: `RenderHealth` (per visual) holds state, fault count, last reason, last fault tick,
  recoveries and a revision that changes on every update. The compositor's state is derived from its
  parts: visual retry gave up, or every layer gave up → placeholder; some layer gave up → degraded;
  anything waiting or retrying → recovering; else healthy. projectM: presentation gave up →
  placeholder; waiting or retrying → recovering; else healthy. A preset load failure is counted with
  no state change (FR-045 already keeps the previous preset playing).
- **Rationale**: One record per visual is what the overlay, the placeholder and the log read; parts
  keep their own retry state.

## PERF-014-D7: The placeholder is an app overlay, faded with a fixed linear 0.5 s ramp

- **Decision**: `RenderPlaceholder` (app) gives the overlay opacity for elapsed time:
  `min(max(t / 0.5, 0), 1)`; SwiftUI animates it linearly over 0.5 s. The overlay is black with a
  small grey "Visual unavailable" note (accessibility label "Visual unavailable"). It is shown only
  while the shown visual's state is placeholder.
- **Rationale**: A monotonic fade is one luminance transition; 0.5 s is slower than the reduce-flashing
  rise limit (0.25 per second would need 0.4 s for 0.10), so even the strict envelope never counts more
  than one transition. An overlay works the same for the compositor and projectM.
- **Flash analysis**: the test samples `L × (1 − opacity)` at 60 fps for a white picture (L = 1) and
  runs `FlashAnalysis.analyze` with the 0.10 threshold: one transition; fade in then out after ≥ 1 s:
  at most one per window.

## PERF-014-D8: Resets

- **Decision**: A compositor visual resets its health parts (`Compositor.resetRenderHealth()`) when its
  frame loop starts (user resume, visual chosen, foreground, presentation return) next to the existing
  `resetFlashHistory()`; a size change re-prepares every layer and resets their parts (CMP-001).
  `retryUnavailableLayers()` becomes the same reset. projectM resets its presentation part in
  `resume()` and `resumeForPresentation()`.
- **Rationale**: These are the user- or system-driven moments the spec names (R6); none happens per
  frame.

## PERF-014-D9: Diagnostics

- **Decision**: `DiagnosticsLog.renderFault(_ summary:)` (one Points of Interest event and one private
  app log line), emitted by the app when a visual's fault count or recovery count changes. The summary
  is `RenderHealth.summary(visual:)`, e.g. `photo recovering layerPrepareFailed faults 2 recoveries 0
  tick 30`: the visual kind, state, reason identifier and counts only.
- **Rationale**: Mirrors PERF-006's event; no user content (R13).

## PERF-014-D10: ANGLERendering depends on Compositor's plain types

- **Decision**: The `ANGLERendering` target adds the `Compositor` product (already a package dependency
  of its `ProjectMLayer` target) to use `RenderHealth`, `RenderRetryState` and `RenderFaultInjection`.
- **Rationale**: One definition of the fault model (Clarifications Q3); no new package.
