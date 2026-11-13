# Contract: Render health and fault recovery (PERF-014)

## Compositor (Packages/Compositor, Metal part)

```swift
public var recoveryPolicy: RenderRecoveryPolicy          // default .standard (30 ticks, 4 retries)
public private(set) var health: RenderHealth             // the visual's record
public private(set) var frameTicks: UInt64               // composite calls with a usable output
public func resetRenderHealth()                          // R6: clear budgets, retry failed parts now
public func retryUnavailableLayers()                     // unchanged signature; now = resetRenderHealth()
#if DEBUG
public var faultInjection: RenderFaultInjection
#endif
```

Per `composite` call with a usable output:

1. `frameTicks += 1`; read finished command buffers from earlier ticks (D2): success → the visual part's
   `succeeded(encodedAt:)`; error → `fault` with the mapped reason.
2. If the composite texture is missing, it is created only when the visual part is not holding
   (allocation failure → fault `missingTexture`, return false).
3. Visual part due → `beginRetry`. Visual part holding → no layer renders; the frame is black.
4. Each layer: due → `beginRetry`, then prepare again if unavailable (pictures again if missing);
   failure → fault (`layerPrepareFailed` / `missingTexture`). Holding or unavailable → fallback (no
   render call). Render success → `succeeded` (recovery when retrying). Serious render error → fault
   `layerRenderFailed` and fallback; routine error → fallback only (CMP-001).
5. The command buffer is remembered with this tick; `health.state` is derived from the parts.

Guarantees: no wait on the GPU; no allocation per tick at a steady size; `prepare` runs only at an
allocation point, a due retry or a reset; outcomes (`LayerOutcome`) keep their CMP-001 meaning.

## ANGLERenderer (Packages/ANGLERendering)

```swift
public private(set) var health: RenderHealth
public private(set) var displayTicks: UInt64
public var onRenderHealthChange: ((RenderHealth) -> Void)?
#if DEBUG
public var faultInjection: RenderFaultInjection
#endif
```

- `setPreset` failure (any `ProjectMEngine` load error, injected or real): `health.recordFault(.presetLoadFailed)`,
  state unchanged, the error is rethrown (FR-045 path unchanged).
- Each display tick: `displayTicks += 1`; presentation part holding → no render unless due; due →
  `beginRetry` and recreate the window surface, then render. Swap failure → fault
  `presentationFailed`; success → `succeeded`. State: gave up → placeholder; waiting/retrying →
  recovering; else healthy.
- `resume()` and `resumeForPresentation()` reset the presentation part.

## App

- Compositor hosts (Camera, Photo, Video, Text) call `compositor.resetRenderHealth()` when their frame
  loop starts and report `compositor.health` through `onRenderHealthChange` when its revision changes
  (checked once per tick, no allocation).
- `AppCoordinator` logs `DiagnosticsLog.renderFault(summary)` when a record's fault or recovery count
  changes, bumps `renderHealthRevision`, and exposes `activeRenderHealth` and `showsRenderPlaceholder`.
- `VisualizerView` shows `RenderPlaceholderView` (black, "Visual unavailable", 0.5 s linear fade) while
  `showsRenderPlaceholder`; `PerformanceOverlay` adds a `render: <debugValue>` line when the record is
  not pristine.
- DEBUG `-uitestRenderFaults <list>` arms every new compositor visual and the renderer; the probe
  (`UITestRenderFaultPanel`) shows `renderHealth`, `renderFaults`, `renderTicks` and a `faults:clear`
  button.

## Diagnostics

`DiagnosticsLog.renderFault(_ summary: String)`: one Points of Interest event "Render fault" and one
private app log line; never from a real-time thread.
