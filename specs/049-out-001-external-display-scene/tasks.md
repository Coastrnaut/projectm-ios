# Tasks: OUT-001 External Display Scene

**Input**: design documents in `specs/049-out-001-external-display-scene/` (spec, plan, research,
data-model, contracts/external-display.md, quickstart).

**Tests**: requested by the spec (OUT-001-S2 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] OUT-001-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical displays; left open.

## Phase 1: Foundational (blocks every story)

- [X] OUT-001-T01 [P] Routing rules: `ExternalDisplayGeometry` (`isUsable`: "width ≥ 1, height ≥ 1, scale > 0, and all three are finite"), `ExternalDisplay`, `ExternalDisplayEvent`, `ExternalDisplayRouting` with `apply(_:) -> Bool`, `active`, `target` per data-model.md, in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalDisplayRouting.swift` — Verified 2026-11-13: `swift test --package-path Packages/PresentationLifecycle` (32 tests, 0 failures)
- [X] OUT-001-T02 [P] Routing tests: no display, connect, not visualizing, zero and non-finite size, background, second display, disconnect hand-over, reconnect, resize reports a change, unknown ids ignored (OUT-001-S3), in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalDisplayRoutingTests.swift` — Verified 2026-11-13: ExternalDisplayRoutingTests 10/10 on the macOS host
- [X] OUT-001-T03 Slots and coordinator: `VisualSlotView`, `VisualSlotHost` (UIViewRepresentable registering the device slot and the current visual), `ExternalDisplayCoordinator` (`registerDeviceSlot`, `show`, `visualizerActive`, `externalConnected/Resized/Foreground/Disconnected`, `place()`, `showsVisualExternally`, `placements`), `ExternalDisplayScenes.affectsDeviceVisuals(role:)`, in `Apps/projectM-iOS/ExternalDisplay/` — Verified 2026-11-13: app builds for the iOS 27.2 simulator; ExternalDisplayCoordinatorTests 9/9

## Phase 2: User Story 1 - The connected display shows only the visualization (P1)

**Goal**: an external display scene shows the visual alone; the device keeps the controls and shows the note.
**Independent test**: the coordinator tests with real slot views, and the UI test with the fake external slot.

- [X] OUT-001-T04 [US1] Scene configuration (revised, research OUT-001-D1): iOS 27 `externalDisplayAccessory` (SwiftUI `ExternalNonInteractiveAccessory` with `ExternalAccessorySlot`) on the root view in `Apps/projectM-iOS/ProjectMApp.swift`, `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayAccessory.swift`; iOS 26 Info.plist manifest in `project.yml` for `ExternalDisplaySceneDelegate`, which creates the window and slot and reports connect, geometry, foreground and disconnect, in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplaySceneDelegate.swift` — Verified 2026-11-13: simulator hot-plug with `simctl io screenConfig`: iOS 27.2 accessory and iOS 26.5 Info.plist role each showed projectM alone on the TVOut screen (docs/test-reports/out-001-external-display.md)
- [X] OUT-001-T05 [US1] Device side: `VisualizerView` hosts every visual through `VisualSlotHost` (identifiers unchanged) and shows `externalDisplayNote` while `showsVisualExternally`; `AppCoordinator` owns the coordinator and reports `visualizerActive` on screen changes, in `Apps/projectM-iOS/Views/VisualizerView.swift`, `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` — Verified 2026-11-13: ExternalDisplayUITests (note shown and hidden) and the iOS 27.2 device screenshot with the note
- [X] OUT-001-T06 [US1] DEBUG fake external display (`-uitestExternalDisplay`: buttons `uitestConnectExternal`, `uitestDisconnectExternal`, a 1920 × 1080 off-screen window at trait display scale 1), in `Apps/projectM-iOS/Debug/UITestExternalDisplay.swift` — Verified 2026-11-13: ExternalDisplayUITests passes through the fake display (10.3 s)
- [X] OUT-001-T07 [US1] App unit tests: the Info.plist scene configuration (external role only, names `ExternalDisplaySceneDelegate`); the visual moves into the external slot and back; a visual change while external goes to the external slot; not visualizing keeps it on the device; the external slot holds only the current visual; `showsVisualExternally` follows the target; each move happens inside the event call, with no later turn of the run loop (OUT-001-R6, checked without wall-clock timing), in `Apps/projectM-iOS/Tests/ExternalDisplayCoordinatorTests.swift` — Verified 2026-11-13: ExternalDisplayCoordinatorTests 9/9 on the iOS 27.2 simulator (0.2 s)

## Phase 3: User Story 2 - Plugging and unplugging never interrupts the music (P1)

**Goal**: connect, disconnect, reconnect and resize never restart the source or stop the camera.
**Independent test**: the UI test counts `sourceStarts`; the unit tests check the Camera host's drawable size and the scene-role filter.

- [X] OUT-001-T08 [US2] Camera and Photo hosts ignore scene connect and disconnect events from external display scenes (`ExternalDisplayScenes.affectsDeviceVisuals`), in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`, `PhotoVisualHost.swift` — Verified 2026-11-13: `testOnlyTheDeviceScenesEventsReachTheDeviceVisuals`, `testCameraVisualRendersAtTheExternalSizeAndComesBackWithoutStopping`, CameraUITests 2/2, PhotoLayerUITests 1/1
- [X] OUT-001-T09 [US2] App unit tests: the Camera visual's (stub camera) drawable becomes 1920 × 1080 × renderScale in the external slot (trait scale 1) and returns to the device size after the move back, without stopping its loop or camera; the scene-role filter, in `Apps/projectM-iOS/Tests/ExternalDisplayCoordinatorTests.swift` — Verified 2026-11-13: `testCameraVisualRendersAtTheExternalSizeAndComesBackWithoutStopping` (drawable 1920 × 1080 × renderScale and back; camera running)
- [X] OUT-001-T10 [US2] UI test: `-autostart inAppPlayback -uitestExternalDisplay`: connect shows `externalDisplayNote`, and the controls still work (pause and resume); disconnect brings the visual back; reconnect; `sourceStarts` stays 1, in `Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift`. The regression run includes the existing `IdleTimerPolicyTests`, `LifecycleCoordinatorTests` and `CameraPrivacyStatusTests`, and the NativeVisual and Camera UI tests (OUT-001-R10: auto-lock, presentation loss and overlays unchanged) — Verified 2026-11-13: ExternalDisplayUITests 1/1 (sourceStarts stays 1); regression: projectM-iOSTests 202 (1 known worktree failure, PresetTests), NativeVisualUITests 4/4, CameraUITests 2/2

## Phase 4: User Story 3 - The big screen is as flash-safe as the device (P1)

**Goal**: the external output is limited by the same envelope, and a move does not reset it.
**Independent test**: GPU tests at a device-like size and at 1920 × 1080.

- [X] OUT-001-T11 [P] [US3] Compositor tests: output at 1920 × 1080 is 1920 × 1080 and reads correct; frames at a steady size create no pictures; a strobe that switches from 390 × 844 to 1920 × 1080 mid-run stays within the transition limit and its gain matches a `FlashEnvelope` fed the whole series (no reset), with and without Reduce flashing (OUT-001-S4, S5), in `Packages/Compositor/Tests/CompositorTests/ExternalOutputSizeTests.swift` — Verified 2026-11-13: `swift test --package-path Packages/Compositor --filter ExternalOutputSizeTests` 3/3 (1.7 s)
- [X] OUT-001-T12 [P] [US3] ANGLE test: a strobe through the renderer's limiter keeps its held gain after the view is resized to an external size (history kept across the resize), in `Packages/ANGLERendering/Tests/ANGLERenderingTests/FlashLimiterTests.swift` — Verified 2026-11-13: ANGLERendering FlashLimiterTests 7/7 on the iOS 27.2 simulator

## Phase 5: Polish and verification

- [X] OUT-001-T13 ADR-0023 "External display scene" (D1-D7) and `docs/adr/README.md` index, in `docs/adr/0023-external-display-scene.md` — Verified 2026-11-13: docs/adr/0023-external-display-scene.md and the README index; `validate_docs.py` OK
- [X] OUT-001-T14 Simulator hot-plug (quickstart B): TVOut display on and off with `simctl io screenConfig`, screenshots of both displays, the app still running; result recorded in `docs/test-reports/out-001-external-display.md` — Verified 2026-11-13: docs/test-reports/out-001-external-display.md (iOS 27.2 and 26.5 simulators)
- [ ] OUT-001-T15 {device} Quickstart C on D1, D2, D3: USB-C/HDMI adapter and AirPlay to an Apple TV; the external display shows the visualization alone and the device keeps the controls (OUT-001-S1, S6)
- [ ] OUT-001-T16 {device} D2 Stage Manager on an extended display: the app's window moves as before; the external scene role is not used for it
- [ ] OUT-001-T17 {device} Hot-plug during playback on D1-D3 (cable and AirPlay): source never restarts, Camera keeps running (OUT-001-S2, S6)
- [ ] OUT-001-T18 {device} Resolution and refresh changes on the Apple TV (60 / 50 / 24 Hz): no crash; record fps for OUT-013

- [X] OUT-001-T19 Gates: `check_compliance.py` and `validate_docs.py` pass; the app builds with no new warnings on the iOS 27.2 SDK here; the iOS 26.5 SDK build runs in CI after integration (OUT-001-R11) — Verified 2026-11-13: `check_compliance.py` OK, `validate_docs.py` OK, and no warning in OUT-001's files in the iOS 27.2 build; the iOS 26.5 SDK build is pending CI (not available here)

## Dependencies

T01 → T02. T01 → T03 → T04, T05, T06, T08 → T07, T09, T10. T11 and T12 are independent. T13 and T14
come after T03-T10. T15-T18 come last (owner).

## Parallel opportunities

T01/T02 with T11 and T12 (different packages); T07 and T09 share one test file (one writer).

## Implementation strategy

MVP = Phase 1 + US1 (the acceptance). US2 hardens hot-plug, and US3 proves flash safety. All three
are P1 and ship together.

## Analysis (speckit-analyze, 2026-11-13)

There were no critical or high findings, and the fixes were applied here:
- E1 (medium): OUT-001-R10 had no task. It is now covered by T10's regression run.
- E2 (low): OUT-001-R6 (0.5 s) cannot be measured by wall clock (brief rule). T07 checks instead that the move is synchronous.
- E3 (low): OUT-001-R11 (both SDKs) had no task. T19 covers it.
- Terminology: "visualizing" (data model) and `visualizerActive` (contract) name the same flag.

Coverage: R1-R12 each have at least one task; S1-S5 map to T07, T10, T11 and T14, and S6 maps to T15-T18.
