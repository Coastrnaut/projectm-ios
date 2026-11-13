# Tasks: OUT-001 External Display Scene

**Input**: design documents in `specs/049-out-001-external-display-scene/` (spec, plan, research,
data-model, contracts/external-display.md, quickstart).

**Tests**: requested by the spec (OUT-001-S2 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] OUT-001-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical displays; left open.

## Phase 1: Foundational (blocks every story)

- [ ] OUT-001-T01 [P] Routing rules: `ExternalDisplayGeometry` (`isUsable`: "width ≥ 1, height ≥ 1, scale > 0, and all three are finite"), `ExternalDisplay`, `ExternalDisplayEvent`, `ExternalDisplayRouting` with `apply(_:) -> Bool`, `active`, `target` per data-model.md, in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalDisplayRouting.swift`
- [ ] OUT-001-T02 [P] Routing tests: no display, connect, not visualizing, zero and non-finite size, background, second display, disconnect hand-over, reconnect, resize reports a change, unknown ids ignored (OUT-001-S3), in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalDisplayRoutingTests.swift`
- [ ] OUT-001-T03 Slots and coordinator: `VisualSlotView`, `VisualSlotHost` (UIViewRepresentable registering the device slot and the current visual), `ExternalDisplayCoordinator` (`registerDeviceSlot`, `show`, `visualizerActive`, `externalConnected/Resized/Foreground/Disconnected`, `place()`, `showsVisualExternally`, `placements`), `ExternalDisplayScenes.affectsDeviceVisuals(role:)`, in `Apps/projectM-iOS/ExternalDisplay/`

## Phase 2: User Story 1 - The connected display shows only the visualization (P1)

**Goal**: an external display scene shows the visual alone; the device keeps the controls and shows the note.
**Independent test**: the coordinator tests with real slot views, and the UI test with the fake external slot.

- [ ] OUT-001-T04 [US1] Scene configuration: `AppDelegate.sceneConfiguration(for:)` (external role → `ExternalDisplaySceneDelegate`, otherwise the session's configuration) and `application(_:configurationForConnecting:options:)`; `@UIApplicationDelegateAdaptor` in `Apps/projectM-iOS/ProjectMApp.swift`; `ExternalDisplaySceneDelegate` creating the window and slot and reporting connect, geometry, foreground and disconnect, in `Apps/projectM-iOS/ExternalDisplay/AppDelegate.swift` and `ExternalDisplaySceneDelegate.swift`
- [ ] OUT-001-T05 [US1] Device side: `VisualizerView` hosts every visual through `VisualSlotHost` (identifiers unchanged) and shows `externalDisplayNote` while `showsVisualExternally`; `AppCoordinator` owns the coordinator and reports `visualizerActive` on screen changes, in `Apps/projectM-iOS/Views/VisualizerView.swift`, `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] OUT-001-T06 [US1] DEBUG fake external display (`-uitestExternalDisplay`: buttons `uitestConnectExternal`, `uitestDisconnectExternal`, a 1920 × 1080 off-screen window at trait display scale 1), in `Apps/projectM-iOS/Debug/UITestExternalDisplay.swift`
- [ ] OUT-001-T07 [US1] App unit tests: the scene configuration per role; the visual moves into the external slot and back; a visual change while external goes to the external slot; not visualizing keeps it on the device; the external slot holds only the current visual; `showsVisualExternally` follows the target, in `Apps/projectM-iOS/Tests/ExternalDisplayCoordinatorTests.swift`

## Phase 3: User Story 2 - Plugging and unplugging never interrupts the music (P1)

**Goal**: connect, disconnect, reconnect and resize never restart the source or stop the camera.
**Independent test**: the UI test counts `sourceStarts`; the unit tests check the Camera host's drawable size and the scene-role filter.

- [ ] OUT-001-T08 [US2] Camera and Photo hosts ignore scene connect and disconnect events from external display scenes (`ExternalDisplayScenes.affectsDeviceVisuals`), in `Apps/projectM-iOS/Visuals/CameraVisualHost.swift`, `PhotoVisualHost.swift`
- [ ] OUT-001-T09 [US2] App unit tests: the Camera visual's (stub camera) drawable becomes 1920 × 1080 × renderScale in the external slot (trait scale 1) and returns to the device size after the move back, without stopping its loop or camera; the scene-role filter, in `Apps/projectM-iOS/Tests/ExternalDisplayCoordinatorTests.swift`
- [ ] OUT-001-T10 [US2] UI test: `-autostart inAppPlayback -uitestExternalDisplay`: connect shows `externalDisplayNote`, and the controls still work (pause and resume); disconnect brings the visual back; reconnect; `sourceStarts` stays 1, in `Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift`

## Phase 4: User Story 3 - The big screen is as flash-safe as the device (P1)

**Goal**: the external output is limited by the same envelope, and a move does not reset it.
**Independent test**: GPU tests at a device-like size and at 1920 × 1080.

- [ ] OUT-001-T11 [P] [US3] Compositor tests: output at 1920 × 1080 is 1920 × 1080 and reads correct; frames at a steady size create no pictures; a strobe that switches from 390 × 844 to 1920 × 1080 mid-run stays within the transition limit and its gain matches a `FlashEnvelope` fed the whole series (no reset), with and without Reduce flashing (OUT-001-S4, S5), in `Packages/Compositor/Tests/CompositorTests/ExternalOutputSizeTests.swift`
- [ ] OUT-001-T12 [P] [US3] ANGLE test: a strobe through the renderer's limiter keeps its held gain after the view is resized to an external size (history kept across the resize), in `Packages/ANGLERendering/Tests/ANGLERenderingTests/FlashLimiterTests.swift`

## Phase 5: Polish and verification

- [ ] OUT-001-T13 ADR-0023 "External display scene" (D1-D7) and `docs/adr/README.md` index; roadmap row note, in `docs/adr/0023-external-display-scene.md`
- [ ] OUT-001-T14 Simulator hot-plug (quickstart B): TVOut display on and off with `simctl io screenConfig`, screenshots of both displays, the app still running; result recorded in `docs/test-reports/out-001-external-display.md`
- [ ] OUT-001-T15 {device} Quickstart C on D1, D2, D3: USB-C/HDMI adapter and AirPlay to an Apple TV; the external display shows the visualization alone and the device keeps the controls (OUT-001-S1, S6)
- [ ] OUT-001-T16 {device} D2 Stage Manager on an extended display: the app's window moves as before; the external scene role is not used for it
- [ ] OUT-001-T17 {device} Hot-plug during playback on D1-D3 (cable and AirPlay): source never restarts, Camera keeps running (OUT-001-S2, S6)
- [ ] OUT-001-T18 {device} Resolution and refresh changes on the Apple TV (60 / 50 / 24 Hz): no crash; record fps for OUT-013

## Dependencies

T01 → T02. T01 → T03 → T04, T05, T06, T08 → T07, T09, T10. T11 and T12 are independent. T13 and T14
come after T03-T10. T15-T18 come last (owner).

## Parallel opportunities

T01/T02 with T11 and T12 (different packages); T07 and T09 share one test file (one writer).

## Implementation strategy

MVP = Phase 1 + US1 (the acceptance). US2 hardens hot-plug, and US3 proves flash safety. All three
are P1 and ship together.
