# Contract: memory pressure recovery (PERF-006)

## Package API (`PresentationLifecycle`)

```swift
public enum MemoryPressureLevel: String, Sendable { case warning, critical }
public enum MemoryPressureTier: String, Sendable { case cache, optional }

public struct MemoryPressureRelease: Equatable, Sendable {
    public var bytes: Int; public var items: Int; public var bytesEstimated: Bool
    public static let none: MemoryPressureRelease
}

@MainActor public protocol MemoryPressureResponder: AnyObject {
    var memoryPressureName: String { get }
    var memoryPressureTier: MemoryPressureTier { get }
    var reclaimableBytes: Int { get }
    func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease
    func restoreAfterMemoryPressure()          // default: nothing
}

@MainActor public final class MemoryPressureRecovery {
    public init(repeatWindowSeconds: Double = 30, coolDownSeconds: Double = 60)
    public func register(_ responder: any MemoryPressureResponder)    // repeats ignored; optional ones shed at once while shedding
    public func unregister(_ responder: any MemoryPressureResponder)
    @discardableResult public func handle(_ level: MemoryPressureLevel, at now: Double) -> MemoryPressureReport?
    @discardableResult public func restoreIfDue(at now: Double) -> [String]
    public private(set) var shedUntil: Double?
    public var isShedding: Bool { get }
    public private(set) var lastReport: MemoryPressureReport?
    public private(set) var recoveries, escalations, restores, totalFreedBytes: Int
    public var snapshot: [(name: String, tier: MemoryPressureTier, reclaimableBytes: Int)] { get }
}
```

Rules:

1. `handle` runs every live cache responder in registration order, then, if escalating, every live
   optional responder not yet shed. Escalating: `level == .critical`, or a previous signal at `t` with
   `now − t ≤ repeatWindow`. Each escalating signal sets `shedUntil = now + coolDown`.
2. A `handle` called from inside a responder is queued and handled after the running one (returns
   nil); the queue is drained before the outer call returns.
3. `restoreIfDue(at:)`: when shedding and `now ≥ shedUntil`, calls `restoreAfterMemoryPressure()` once
   on every shed responder still alive, clears the shed state, returns their names; otherwise `[]`.
4. Responders are weak; released ones are skipped and pruned.
5. The report's `freedBytes` is the sum of its steps' bytes; `MemoryPressureReport.summary` is the
   diagnostics text (names and counts only).

## App (`projectM-iOS`)

- `MemoryPressureCoordinator.shared` observes `UIApplication.didReceiveMemoryWarningNotification`
  (main queue) and calls `handle(.warning)`. Nothing else in the app observes it.
- After an escalating report it schedules one restore task for `shedUntil`.
- Every report is logged with `DiagnosticsLog.memoryRecovery(summary)`.
- Steps registered: shared texture pool (on first pool), renderer's `memoryPressureResponders` (in
  `prepareRenderer`), the preset loader's archive cache, the idle native spectrum (AppCoordinator).

## Renderer (`Rendering`, `ANGLERendering`)

- `VisualizerRenderer.memoryPressureResponders: [any MemoryPressureResponder]` (default `[]`).
- `ANGLERenderer` returns `[warm-up context (cache), warm-up (optional)]`.
- Warm-up cache step: cancel a waiting request, `worker.stop()` (thread, context, engine, target
  released before it returns), keep the last request and the warmed IDs. Release reports 1 item and
  `PresetPrewarmer.targetSize² × 4` estimated bytes when the worker held its graphics resources or was
  running; otherwise `.none`.
- Warm-up optional step: as the cache step, then hold requests (remember the newest) until
  `restoreAfterMemoryPressure()`, which schedules the newest with the normal delay unless the app
  cannot present (PERF-011 suspension wins; resume then schedules it).

## DEBUG probe (`-uitestMemoryPressure`)

| Identifier | Kind | Meaning |
|---|---|---|
| `memory:warning` | button | posts `UIApplication.didReceiveMemoryWarningNotification` |
| `memory:critical` | button | `MemoryPressureCoordinator.shared.handle(.critical)` |
| `memoryRecoveries` | value | recoveries so far |
| `memoryFreedBytes` | value | last report's freed bytes (`-1` before any) |
| `memoryRetiredBytes` | value | retired bytes in the shared pools now |
| `memoryWarmUpContext` | value | `yes` / `no`: the warm-up holds its graphics resources |
| `visualFrames` | value | frames presented by the shown visual |

Under the flag the shared pool's idle-age limit is raised (research PERF-006-D7).
