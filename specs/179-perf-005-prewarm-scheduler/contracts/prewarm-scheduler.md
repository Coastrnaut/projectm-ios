# Contract: prewarm scheduler (PERF-005)

## Core (`PresentationLifecycle`)

- `PrewarmScheduler(budgetBytes:executor:clock:loader:settleDelay:)`
- `plan(_ items: [PrewarmItem], live: Set<PrewarmKey>)` — replaces the plan (R2). Low Power (`lowPower = true`) keeps rank 0 only (R9).
- `pause(_:)` / `resume(_:)` — `.presentation` cancels the in-flight item, waits for a running graphics step and releases non-live entries (R6).
- `take(_ key) -> PrewarmedAsset?` — removes the entry from the accounting (R4).
- `releaseForMemoryPressure() -> (bytes: Int, items: Int)` — releases every non-live entry and cancels the in-flight item (R10).
- `forwardPresets(_ ids: [String], _ forward: () -> Void)` — calls `forward` before returning; no clock use (R8).
- `shutdown()`.
- `PrewarmLoading.load(_ item, context) -> PrewarmLoadResult` runs on the executor; `context.isCancelled`, `context.maxBytes`, `context.graphicsStep { }` (nil when refused).
- `PrewarmExecutor.execute(_:)`; default `DispatchPrewarmExecutor` (serial, `.utility`).
- `PrewarmClock.schedule(after:_:) -> PrewarmClockToken`; default `DispatchPrewarmClock`.

## Photo layer (`ImageLayer`)

- `ImageLayerSource.prewarmedTexture: ((URL) -> MTLTexture?)?` — consulted when `content` becomes `.file(url)` and no MED-006 prepared texture exists; a hit sets the state to ready at once with no load (R11).
- `ImageLayerSource.loadsStarted` — loads the layer started itself.
- `ImageLayerSource.decodeStored(_:decoder:limits:)` and `makeLayerTexture(_:device:)` — the two halves of a load.

## App

- `MediaPrewarmCoordinator`: presentation-bound resource "media prewarm", PERF-006 cache responder "media prewarm cache", `replan(cues:activeIndex:photoURL:liveURL:)`, `takeTexture(_ url)`.
