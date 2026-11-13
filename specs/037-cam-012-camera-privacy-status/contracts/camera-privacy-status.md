# Contract: Camera privacy status (app-internal and UI)

## `CameraIndicator` (app, value type)

```swift
struct CameraIndicator: Equatable {
    init(state: CameraFeedState)
    let isShown: Bool                 // .starting or .running
    let accessibilityValue: String    // "Starting" | "Live"
    static let label = "Camera on"
    static let stopTitle = "Stop camera"
    static let stoppedAnnouncement = "Camera off"
}
```

## `CameraVisualHost`

- `func stopCamera()`: the user's Stop. When it returns the provider has been told to stop
  exactly once (if it was not idle), its state is `.idle`, no picture is held, and `feedState`
  is `.idle` (reported through `onFeedStateChange`). The frame loop keeps running if it was.
  Later `resume()`, foreground, scene and presentation events never start the camera again on
  this host.
- `var cameraStoppedByUser: Bool { get }`
- `var framesComposited: Int { get }`: frames presented by the loop (tests, diagnostics).

## `AppSettings`

- `var visualBeforeCamera: VisualChoice { get }`: the stored visual key, projectM when absent or
  `camera`.

## `AppCoordinator`

- `var cameraIndicator: CameraIndicator`: `CameraIndicator(state: cameraState)`, shown only while
  `showsCameraVisual`.
- `func stopCamera()`: no-op unless the Camera visual exists. Calls the host's `stopCamera()`,
  posts "Camera off", sets `settings.visual = settings.visualBeforeCamera`, and calls
  `visualSettingsChanged()` (releases the host, resumes the fallback). Never touches the audio
  source.

## UI (accessibility identifiers)

| Element | Identifier | Label | Value |
|---|---|---|---|
| Badge container | `cameraIndicator` | "Camera on" | "Live" / "Starting" |
| Stop button | `stopCamera` | "Stop camera" | — |

The badge is shown whenever `coordinator.cameraIndicator.isShown`, independent of the controls.
