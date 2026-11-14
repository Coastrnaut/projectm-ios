# Contract: PRE-001 thumbnail cache

## C1 `PresetThumbnailRendering` (PresetLibrary)

```swift
public protocol PresetThumbnailRendering: Sendable {
    /// PNG bytes of `contents` drawn per `spec`. Throws `PresetThumbnailError.unavailable` when no
    /// drawing can happen now (not remembered), any other error when the preset cannot be drawn.
    func render(_ contents: Data, spec: PresetThumbnailSpec) async throws -> Data
}
```

## C2 `PresetThumbnailCache` (actor, PresetLibrary)

- `init(directory:renderer:spec:pause:maxPending:sleep:)` — defaults: `.standard`, 150 ms, 32, `Task.sleep`.
- `open()` — reads and repairs the index (data-model "Open-time repair"); never throws.
- `cachedURL(for:) -> URL?` — the file for a valid entry, without queuing.
- `thumbnail(for:contents:) async throws -> URL` — a hit returns at once; a miss queues (C3) and returns the written file. Errors: `CancellationError` (caller cancelled), `PresetThumbnailError.dropped`, `.unavailable`, `.failed` (this session).
- `renderCount` — renders started since `init` (tests and automation).
- `pendingCount` — waiting requests.

## C3 Queue rules

1. One pending entry per stable ID; a repeat adds a waiter and makes the entry newest.
2. The worker serves the newest entry first, one at a time, then sleeps `pause`.
3. More than `maxPending` entries → the oldest is removed, its waiters get `.dropped`.
4. A cancelled waiter is removed; an entry left without waiters is removed before rendering.
5. A finished render answers every waiter of its entry and is cached even if all of them left.

## C4 `PresetThumbnailDrawing` (Rendering) and the ANGLE runner

```swift
public enum PresetThumbnailDrawResult: Sendable, Equatable {
    case pixels(Data)          // RGBA8, top row first, width × height × 4 bytes
    case failed(String)
    case unavailable(String)
}
public protocol PresetThumbnailDrawing: AnyObject, Sendable {
    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult
}
// VisualizerRenderer: var presetThumbnails: (any PresetThumbnailDrawing)? { get }  (default nil)
```

`ANGLERenderer` returns its `PresetThumbnailRunner`, applies its texture paths, suspends it with
PERF-011 presentation loss (a running draw stops at its next frame and answers `unavailable`) and
shuts it down with the renderer.

## C5 The row (app)

- `PresetRow` shows `PresetThumbnailView` first; image identifier `thumbnail:<name>`, placeholder `thumbnailPlaceholder:<name>`; both hidden from VoiceOver.
- Requests only for playable presets; locked presets show the lock placeholder.
