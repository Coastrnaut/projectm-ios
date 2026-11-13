# Contract: External display scene (OUT-001)

## Scene configuration

| Connecting session role | Configuration returned by `AppDelegate` |
|---|---|
| `.windowExternalDisplayNonInteractive` | name "External display", delegate `ExternalDisplaySceneDelegate` |
| any other (`.windowApplication`, …) | the session's own configuration (SwiftUI's window group) |

## ExternalDisplaySceneDelegate → ExternalDisplayCoordinator

| UIKit callback | Coordinator call |
|---|---|
| `scene(_:willConnectTo:options:)` | creates `UIWindow(windowScene:)`, root view a black external `VisualSlotView`, `isHidden = false`; `externalConnected(id:slot:geometry:foreground:)` |
| `windowScene(_:didUpdateEffectiveGeometry:)` and the slot's layout | `externalResized(id:geometry:)` (points from the window bounds, scale from the screen's trait display scale) |
| `sceneWillEnterForeground` / `sceneDidEnterBackground` | `externalForeground(id:_:)` |
| `sceneDidDisconnect` | `externalDisconnected(id:)`; the window is released |

## ExternalDisplayCoordinator (app, main actor)

- `registerDeviceSlot(_:)` / `unregisterDeviceSlot(_:)`: called by `VisualSlotHost`.
- `show(_ visual: UIView?)`: the current visual view (nil when no visual).
- `visualizerActive(_:)`: from `AppCoordinator` (on the visualizer screen or not).
- After every call, `place()` puts `visual` in the target slot, or in no slot when that slot is
  missing, and removes stale visual views from the other slots.
- `showsVisualExternally: Bool`: the visual is on an external display. `VisualizerView` shows the
  note `externalDisplayNote` ("Showing on external display") and no live visual on the device.
- It never touches the audio source, the renderer's pause state or the presentation registry.

## Device UI

- The note is a centred caption over black with accessibility identifier `externalDisplayNote`.
  Its label is "The visualization is showing on the external display".
- The controls, badges, banners, sheets, the tap target and overlays are unchanged.
- The identifiers of the visual (`visualizer`, `circularSpectrum`, `linearSpectrum`,
  `cameraVisual`, `photoVisual`) stay on the device's slot host, so UI tests find the shown visual
  on either display.

## DEBUG test hooks

`-uitestExternalDisplay` adds a debug panel with buttons `uitestConnectExternal` and
`uitestDisconnectExternal`. They drive the coordinator with a fake external slot: an off-screen
1920 × 1080 window at trait display scale 1, created on the app's window scene.
