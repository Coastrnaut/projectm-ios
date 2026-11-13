# Research: OUT-001 External Display Scene

All decisions below are Claude's under owner rule 4 (best judgement), 2026-11-13.

## OUT-001-D1 Scene API (revised during implementation, 2026-11-13)

- **Decision**:
  - **iOS 27 and later**: the SwiftUI scene accessory
    `View.sceneAccessory { ExternalNonInteractiveAccessory { ExternalAccessorySlot } }`. This is
    new in the iOS 27.0 SDK: `UISceneAccessory` / `UIViewController.registerSceneAccessory` in
    UIKit, and `SceneAccessoryContent` / `ExternalNonInteractiveAccessory` in SwiftUI. It is
    applied to the root view in `ProjectMApp`, compiled only with Swift ≥ 6.4 (the iOS 27 SDK),
    and guarded at run time with `#available(iOS 27.0, *)`.
  - **iOS 26**: `UIWindowSceneSessionRoleExternalDisplayNonInteractive` (iOS 16+). Info.plist's
    `UIApplicationSceneManifest` names `ExternalDisplaySceneDelegate` for that role only.
    `UIApplicationSupportsMultipleScenes` is false, and the application role is not configured, so
    it stays with SwiftUI.
- **Evidence**:
  1. The iOS 27.2 SDK still declares the role with `API_AVAILABLE(ios(16.0))` and no deprecation.
     Its headers add `UISceneAccessory.h`, which describes "supplementary content that the system
     presents on the app's behalf when … an external display is connected". The SwiftUI interface
     has `ExternalNonInteractiveAccessory` and `View.sceneAccessory` (`@available(iOS 27.0, *)`).
  2. iOS 27.2 simulator, plist role only: connecting the TVOut screen
     (`simctl io … screenConfig --display external power on`) gave the app no scene. SpringBoard
     logged that it registered the app's "NonInteractive" presentation, dropped it within about
     10 ms, and fell back to `mirroredDisplay`. With the accessory, the slot connected at 720 × 480
     @1, and the external screenshot showed projectM alone.
  3. iOS 26.5 simulator, the same build: the plist role connected `ExternalDisplaySceneDelegate`
     ("external display scene connecting (role UIWindowSceneSessionRoleExternalDisplayNonInteractive)"),
     and the external screenshot showed projectM alone. The accessory code does not run there.
  4. The first attempt, a `UIApplicationDelegateAdaptor` whose `configurationForConnecting`
     returned the session's own configuration for the application role, left SwiftUI's window empty
     (a white screen) on the iOS 27.2 simulator. The plist manifest replaced it.
- **Alternatives**:
  - The accessory only: iOS 26 (D3) would mirror.
  - The plist role only: iOS 27 mirrors (evidence 2).
  - `UIScreen.didConnectNotification` with a manual `UIWindow`: the pre-scene approach, which
    scene-based apps do not use.

## OUT-001-D2 Rendering: move the one visual, do not render twice

- **Decision**: Option (b). While an external display is the target, the visual's own view moves
  into the external window. The device shows black with the note, under the controls. One renderer
  or compositor draws one frame per tick, at the external screen's size and scale.
- **Evidence**:
  - *Cost*: on D1, only 22 of 28 starter presets reach 55 fps under ANGLE, and the slowest runs
    at 26 fps (`docs/test-reports/performance.md`). A second draw per frame would push most
    presets under the 30 fps floor.
  - *ANGLE constraints*: `ANGLERenderer` owns one EGL context and one projectM engine, with one
    window surface on its view's `CAMetalLayer`. The surface is recreated whenever the drawable
    size changes (`layoutSurface`). Engine state (preset, blend, beat detection, the
    per-frame/per-vertex equation state) lives inside the engine and cannot be shared with a
    second context. A second engine would drift from the first and double the engine work.
  - *Compositor visuals*: the compositor reallocates its pictures once per output size
    (CMP-001-R9, `testResizeReallocatesExactlyOncePerSize`). Alternating two sizes per frame
    would reallocate every frame. Two compositors would double the layer work and open a second
    camera session, which the camera kind forbids (one instance per stack, CAM-001).
  - *Moving is already supported*: every visual lays out its drawable from
    `view.bounds × traitCollection.displayScale × QualityGovernor.renderScale` on layout. The
    ANGLE view starts its display link on `didMoveToWindow` and stops it when the view leaves a
    window. The compositor hosts skip frames while the view has no window.
- **Alternatives**: rendering twice (rejected above); mirroring by copying the device drawable
  (not the external resolution, and the extra copy costs GPU time).

## OUT-001-D3 Who owns the visual view

- **Decision**: SwiftUI hosts a `VisualSlotView` (a plain container) through `VisualSlotHost`,
  never the visual view itself. The external window's root view is another `VisualSlotView`. The
  coordinator keeps weak references to the device slot, the external slot and the current visual
  view. On every change it places the view in the target slot: it removes any other visual view
  from that slot, adds the view filling the slot, and calls `setNeedsLayout`, so the drawable is
  laid out again for the new size and scale.
- **Why**: if SwiftUI owned the visual view (as `makeUIView { view }` does today), dismantling its
  representable could pull the view out of the external window, and a reparented view would
  confuse SwiftUI's layout. Containers make the ownership explicit and testable.

## OUT-001-D4 Scene events from the external display

- **Decision**: `CameraVisualHost` and `PhotoVisualHost` observe `UIScene.didDisconnectNotification`
  and `willConnectNotification` for every scene. They now ignore scenes whose session role is
  external display (`ExternalDisplayScenes.affectsDeviceVisuals(role:)`).
- **Why**: without the filter, unplugging a display would stop the camera for good (OUT-001-R9,
  CAM-001-R7). App-level notifications (background, foreground, protected data) are unchanged, and
  so is the SwiftUI `scenePhase` of the device's window group (FR-084, PERF-011).

## OUT-001-D5 Flash safety

- **Decision**: no new flash code. The external output is the same renderer's or compositor's
  output, so it goes through the ANGLE post-pass (projectM) or the composite flash guard
  (compositor visuals) with the app's Reduce flashing setting. Moving the view keeps the history:
  - `PMFlashLimiterBegin` keeps the envelope's history across a resize (FlashLimiter.c, FX-019-R11).
  - The limiter is destroyed only on presentation loss (PERF-011).
  - The compositor hosts' frame loops are not restarted by a move, so `resetFlashHistory()` is not
    called.

  New tests check both (`ExternalOutputSizeTests`, the ANGLE resize test).

## OUT-001-D6 Simulator verification

- **Finding**: Xcode 27.2's `simctl io` has `screenConfig --display <id|external> power on|off` and
  `geometry WxH`. `enumerate` lists a "TVOut" screen (`external-0`, 720 × 480 at scale 1).
  `xcrun simctl io <udid> screenConfig --display external power on` connects it to a booted
  simulator, and `screenshot --display external` captures it. Hot-plug can therefore be scripted
  headless, without the Simulator app's I/O menu or the Simulator panel tool (owner rule 8).
  (Turning on the second port, "Wireless", gives a CarPlay screen, which is not used.)
- **Use**: quickstart scenario B (connect, screenshot both displays, disconnect, while the app runs
  with `-autostart`). The XCUITest runner cannot run `simctl`, so the UI test uses a DEBUG fake
  external slot (`-uitestExternalDisplay`) that drives the same coordinator path.

## OUT-001-D7 Frame pacing and resolution

- **Decision**: the visual keeps its own `CADisplayLink` (main display, ≤ 60 fps, FR-049). The
  drawable takes the external screen's native size and scale with no cap. A 60 Hz loop feeding a
  50 Hz or 24 Hz display may wait for drawables; measuring that is a `{device}` task. The fixes
  belong to OUT-013 (per-output pacing) and OUT-003 (output scale).
- **Alternatives**: `UIScreen.displayLink` of the external screen (changes every visual's loop;
  OUT-013's scope).
