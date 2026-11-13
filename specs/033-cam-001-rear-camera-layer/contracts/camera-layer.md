# Contract: Camera layer and frame providers (CAM-001)

Extends `specs/029-cmp-001-unified-layer-protocol/contracts/layer-source.md`; nothing there changes.

## CameraFrameProvider

```swift
public protocol CameraFrameProvider: AnyObject {
    /// Current state (main thread).
    var state: CameraFeedState { get }
    /// Called on the main thread whenever `state` changes.
    var onStateChange: ((CameraFeedState) -> Void)? { get set }
    /// Starts (asks for access only when it was never decided and a back camera exists). Main thread.
    func start()
    /// Stops at once: no more pictures, the latest is dropped, state `idle`. Main thread. Idempotent.
    func stop()
    /// The newest picture, or nil. Any thread; never blocks (returns nil on lock contention).
    func latestFrame() -> CameraFrame?
}
```

Rules: `start()` while running is a no-op; `stop()` before `start()` is a no-op; after `stop()`
`latestFrame()` returns nil until the next picture of a new `start()`. A provider never writes a
picture to storage, sends it, or analyses it.

## CameraLayerSource: LayerSource

- `layerName` "camera"; `fallback` `.transparent`; identity composite settings.
- `prepare` builds its pipeline (once) and sampler for the layer format; throws
  `.resourceUnavailable` if Metal cannot.
- `render`: if `provider.state` is not `running` → throws `.notReady` (no frozen picture). If no
  picture has arrived yet → `.notReady`. Otherwise clears the picture to transparent and draws one
  full-screen triangle sampling the camera texture with `CameraPictureGeometry` (aspect fill,
  rotation); output alpha 1 (premultiplied identity). On lock contention it draws the picture it
  used last frame (held only while running). Allocates nothing; `setFragmentBytes` only.
- `start()` / `stop()` forward to the provider; `stop()` also drops the held picture.
- `framesShown`: frames whose own picture was drawn (diagnostics and tests).

## App host (CameraVisualHost)

- `resume()` → provider `start()` + frame loop; `pause()` / presentation suspension / scene
  disconnect → provider `stop()` + loop stopped, before returning.
- `feedState` mirrors the provider; `onFeedStateChange` tells the coordinator.
- View: accessibility label "Camera visualization", identifier `cameraVisual`, value from
  `CameraFeedState.accessibilityValue`.

## UI (VisualizerView)

- Banner identifier `cameraNotice` with the state's notice text; button `cameraOpenSettings`
  ("Open Settings", opens `UIApplication.openSettingsURLString`) for denied and restricted.
- `-uitestDiagnostics`: hidden text `cameraFramesShown` whose value is the host's `framesShown`,
  refreshed twice a second.
- DEBUG `-uitestCamera <scenario>` selects `StubCameraFrameProvider`.
