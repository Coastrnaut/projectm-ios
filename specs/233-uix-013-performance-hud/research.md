# Research: UIX-013 Scene Performance HUD

## UIX-013-D1: Why the HUD can never reach the output

- **Decision**: Draw the HUD as a SwiftUI view in the device window's status stack (`VisualizerView.topStatus`) and nowhere else. No option to include it.
- **Rationale**: OUT-001 moves the visual's own `UIView` into a `VisualSlotView` that is the external window's only content (`ExternalDisplayViewController`, the iOS 27 accessory slot); SwiftUI overlays stay in the device window. REC-003 and REC-001 read the visual's Metal output inside its frame's command buffer (compositor `encodeOutput`, drawable blit, ANGLE capture), which SwiftUI layers are never drawn into (REC-009-D1 proved this for its overlay). OUT-012's rehearsal preview draws a test grid, not the device overlays.
- **Alternatives considered**: drawing the HUD into the compositor as a layer with an "exclude from output" flag (rejected: needs a second render pass and risks leaks); a separate UIWindow (rejected: no benefit, more state).

## UIX-013-D2: How exclusion is proven

- **Decision**: Three app tests with real views: (1) an external window built from `ExternalDisplayViewController` holding a solid-colour visual, with the real `SceneHUDLayer` hosted in a device window: the external window's view tree contains no hosting view or HUD element, and its snapshot is byte-identical with the HUD on and off; (2) a red Photo visual recorded through `VideoRecordingCoordinator` while the HUD and a green probe are on screen in the same window: no probe pixel in any frame, and each decoded frame equals the matching frame of a HUD-off recording; (3) `FrameCaptureCoordinator`'s source (the same Photo visual) captured with the HUD on and off: identical pixels.
- **Rationale**: follows REC-009-T08's proven pattern; deterministic (solid picture, no audio reader), no wall-clock assertions.
- **Alternatives considered**: UI-test screenshots of a simulated external display (rejected: the simulator's external display path differs between iOS 26 and 27 and is not device evidence anyway).

## UIX-013-D3: Placement

- **Decision**: First item of the top status stack, `frame(maxWidth: 360)`, inside the stack's existing padding (safe area + UIX-005 reserved insets) and the UIX-007 output pane. The stack's `Spacer` keeps it in the top band.
- **Rationale**: reuses the layout every badge already obeys; nothing new to keep in sync.

## UIX-013-D4: Preference storage

- **Decision**: Standalone `SceneHUDSetting` (like REC-007's `RecordingCountdownSetting`), key `settings.visualizer.sceneHUD`, Bool, default off; FILE-005 `includedKeys`; `-uitestResetNotice` removes it; listed in `ALLOWED_KEYS` and in `LibraryBackupAppTests`' app keys (it lives outside `AppSettings.allKeys`).
- **Rationale**: avoids editing `AppSettings` (shared hot file); a preference, not a device capability, so it is backed up.

## UIX-013-D5: Tempo source naming

- **Decision**: `TempoReadout.manual` → "Tap"; `.stable`/`.uncertain` → "Estimated" (with SHOW-011's "≈" for uncertain); `.searching` → "None". Spoken: "120 BPM from tap", "about 118 BPM, estimated", "no tempo".
