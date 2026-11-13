# Contract: External display scene (OUT-001)

## Scene configuration

| OS | Mechanism | External window |
|---|---|---|
| iOS 27+ | `RootView.externalDisplayAccessory(_:)` → `sceneAccessory { ExternalNonInteractiveAccessory { ExternalAccessorySlot } }` | the accessory's SwiftUI content: one external `VisualSlotView` |
| iOS 26 | Info.plist `UIApplicationSceneManifest`: `UISceneConfigurations` has only `UIWindowSceneSessionRoleExternalDisplayNonInteractive` → `$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate`; `UIApplicationSupportsMultipleScenes` false | `UIWindow(windowScene:)` with `ExternalDisplayViewController` (its view is the slot) |

## Events → ExternalDisplayCoordinator

| Source | Coordinator call |
|---|---|
| Accessory slot enters a window / delegate `scene(_:willConnectTo:options:)` | `externalConnected(id:slot:geometry:foreground:)` |
| Slot layout or display-scale trait change | `externalResized(id:geometry:)` (points from the slot's bounds, scale from its trait display scale) |
| The window scene's `willEnterForeground` / `didEnterBackground` (accessory: its own scene's notifications; delegate: `sceneWillEnterForeground` / `sceneDidEnterBackground`) | `externalForeground(id:_:)` |
| Accessory slot leaves its window or is dismantled / delegate `sceneDidDisconnect` | `externalDisconnected(id:)` |

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
