# Tasks: OUT-010 Output Blackout Isolation

**Input**: design documents in `specs/051-out-010-output-blackout-isolation/` (spec, plan, research,
data-model, contracts/output-blackout.md, quickstart).

**Tests**: requested by the spec (OUT-010-S1 to S4) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] OUT-010-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical displays; left open.

## Phase 1: Foundational (blocks every story)

- [ ] OUT-010-T01 [P] State machine `OutputBlackout` (phases, `blackOut`, `restore`, `advance(frameTime:reduceFlashing:)`, `coverOpacity` = 1 − sRGBEncode(f), `needsFrames`, constants) per data-model.md and contracts/output-blackout.md, in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputBlackout.swift`
- [ ] OUT-010-T02 [P] Test dependency of `PresentationLifecycleTests` on `FlashSafety` (path dependency, test target only), in `Packages/PresentationLifecycle/Package.swift`
- [ ] OUT-010-T03 Cover layer in every slot: black `CALayer` above all subviews, opacity set with actions disabled, frame follows the bounds, `coverOpacity` and `isOutputBlack` for tests; `hold` and `removeVisuals` leave it in place, in `Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift`

## Phase 2: User Story 1 - Black out the projected picture at once (P1)

**Goal**: one tap makes the output black at the next frame; the controls keep working; the source is untouched.
**Independent test**: model tests with a fake frame clock, coordinator tests with real slots, the UI test with the fake external display.

- [ ] OUT-010-T04 [US1] Model tests: blackout from every phase makes the next frame black (fake 60 Hz clock, blackout between frames); restore never raises the factor without a frame; frame-time clamping (NaN, negative, 5 s stall), in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputBlackoutTests.swift`
- [ ] OUT-010-T05 [US1] Coordinator: `blackout` model, observable `blackoutPhase`, `setBlackout(_:)`, `toggleBlackout()`, `reduceFlashing`, `applyCovers()` on every change and at the start of `place()`, `advanceFrame(frameTime:)`, a `CADisplayLink` through a weak proxy only while `needsFrames`, in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`; `AppCoordinator` passes Reduce flashing, in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] OUT-010-T06 [US1] UI: Black out / Restore output control with label and value in `Apps/projectM-iOS/Views/ControlsOverlay.swift`; persistent `blackoutBadge` with `blackoutRestore`, the "External display blacked out" note, DEBUG probes `outputBlackout` and `visualRunning`, in `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] OUT-010-T07 [US1] App unit tests: the target slot's cover is opaque with no animation key before `setBlackout(true)` returns, on the device and on the external slot; the visual stays in its slot (no placement); a half-opaque cover over white composites in encoded values (research OUT-010-D2), in `Apps/projectM-iOS/Tests/OutputBlackoutCoordinatorTests.swift`
- [ ] OUT-010-T08 [US1] UI test (`-uitestExternalDisplay -uitestDiagnostics -autostart inAppPlayback`): connect; Black out; `outputBlackout` = `black`; Settings opens and closes and pause/resume work while blacked out; Restore; `outputBlackout` returns to `live`; `visualRunning` = `yes`; `sourceStarts` stays 1, in `Apps/projectM-iOS/UITests/OutputBlackoutUITests.swift`

## Phase 3: User Story 2 - Restore without a flash (P1)

**Goal**: restore fades in within the envelope's limits; toggling cannot strobe.
**Independent test**: model tests measured with `FlashAnalysis` on a white picture.

- [ ] OUT-010-T09 [US2] Fade and spacing tests: the fade lasts 1 s / 4 s of frame time; a white picture's luminance rises at most 0.25 per second with Reduce flashing on; a restore within 1 s of the previous start waits black and then fades; blackout during a fade or a wait is black at the next frame; fastest toggling (a tap every frame, and a tap every 0.15 s) for 5 s stays within 4 transitions per 1 s window (both settings) measured with `FlashAnalysis`, in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputBlackoutTests.swift`
- [ ] OUT-010-T10 [US2] Coordinator fade test: `advanceFrame` steps move the cover from 1 to 0 over the fade, the phase returns to `live`, and `needsFrames` turns off after the spacing, in `Apps/projectM-iOS/Tests/OutputBlackoutCoordinatorTests.swift`

## Phase 4: User Story 3 - The blackout follows the output (P2)

**Goal**: connect, disconnect, visual change and visualizer re-entry never reveal the picture.
**Independent test**: coordinator tests with real slot views.

- [ ] OUT-010-T11 [US3] Coordinator tests while blacked out: connect (external slot black when it receives the visual), disconnect (device slot black when the visual returns), a new device slot after re-entering the visualizer, a visual change, external background; and restore after each, in `Apps/projectM-iOS/Tests/OutputBlackoutCoordinatorTests.swift`

## Phase 5: Polish and verification

- [ ] OUT-010-T12 ADR-0023 decision 8 (blackout: mechanism, no device preview, keeps rendering, fade, spacing, the residual flash limitation), in `docs/adr/0023-external-display-scene.md`
- [ ] OUT-010-T13 Regression on the iOS 27.2 simulator: projectM-iOSTests, OutputBlackoutUITests, ExternalDisplayUITests, NativeVisualUITests; `swift test` PresentationLifecycle on the host; `check_compliance.py`, `validate_docs.py`; PosterBoard reports counted before and after
- [ ] OUT-010-T14 Headless real-screen check (quickstart C): `simctl io screenConfig` external on, blackout, `screenshot --display external` black, restore, screenshot shows the visual; result recorded in `docs/test-reports/out-010-output-blackout.md`
- [ ] OUT-010-T15 {device} Blackout on HDMI (USB-C adapter) and AirPlay on D1 and D2 (quickstart D): black at once, controls responsive, restore fade, unplug while blacked out keeps the device black; optional 240 fps camera timing
