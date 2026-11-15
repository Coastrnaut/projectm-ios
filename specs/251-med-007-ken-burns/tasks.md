# Tasks: MED-007 Image Ken Burns

**Input**: Design documents from `specs/251-med-007-ken-burns/` (spec, plan, research, data-model,
contracts/ken-burns.md, quickstart).

**Tests**: requested by the spec (acceptance: "Start/end frames match specified crop rectangles"; MED-007-S1 to S5).
Budgets (owner rule 7): unit test ≤ 2 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] MED-007-T01 Create the private simulator "MED7 iPhone 17" (iOS 27.2), count PosterBoard reports, check the `Build` symlink and the preset submodules, run `xcodegen generate` in the worktree

## Phase 2: Foundational (model)

- [ ] MED-007-T02 Add `KenBurnsRect` ("width/height ≥ 0.05, x, y ≥ 0, x + width ≤ 1, y + height ≤ 1 (1e-9 tolerance)", `clamped`, `init?(validating:)`, `full`, `lerp`), `KenBurnsEasing` (`linear`, `easeInOut` = 3u² − 2u³), `KenBurnsMotion` ("durationMilliseconds 2000…60000, default 10000", default easing easeInOut, `crop(elapsedNanoseconds:durationNanoseconds:)` exact at 0 and ≥ duration, presets `zoomIn`/`zoomOut`/`panLeftToRight`/`panRightToLeft`, Codable with the scene keys) and `KenBurnsPlayhead` in `Packages/Compositor/Sources/Compositor/KenBurns.swift`
- [ ] MED-007-T03 Model tests in `Packages/Compositor/Tests/CompositorTests/KenBurnsModelTests.swift`: exact start and end (bit-equal), monotonic edges over a run for both easings and every preset, intermediate rectangles valid, validation and clamping, playhead (frame durations, saturation, restart), JSON round trip and malformed JSON (MED-007-S2)

## Phase 3: User Story 1 - A photo zooms and pans (P1) 🎯 MVP

**Goal**: the photo layer samples the interpolated crop on the injected clock.
**Independent Test**: `swift test --package-path Packages/Compositor --filter KenBurns`.

- [ ] MED-007-T04 [US1] `ImagePictureGeometry(_ placement:, crop:)` and a `bounds` field (`Packages/Compositor/Sources/ImageLayer/ImagePictureGeometry.swift`); in `Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift`: `kenBurns`, `kenBurnsDurationNanoseconds`, `reduceMotion`, the playhead (restart on a new held picture or movement, advance in `render`), placement on the crop size (pixel-accurate read as fit), the `bounds` uniform in the shader, CMP-013 dependencies (time while moving; still with a parameter generation otherwise)
- [ ] MED-007-T05 [US1] GPU acceptance in `Packages/Compositor/Tests/CompositorTests/KenBurnsLayerTests.swift`: first frame vs. the CPU crop of a 1:1 start rectangle (every pixel within 1/255 in linear light), the frame at the end time vs. a 2× end rectangle of a block image (pixels away from block edges within 1/255), a middle frame differs from both; Reduce Motion frames equal the start; caching renders every frame while moving and reuses once holding; Ken Burns off draws as before (MED-007-S1, S4)

## Phase 4: User Story 2 - Choose the movement in Settings (P1)

- [ ] MED-007-T06 [US2] `KenBurnsStore` (`settings.photo.kenBurns`, absent = off) and `KenBurnsCoordinator` (on/off, preset choice, custom start/end zoom 100…400 % and position 0…100 %, duration 2…60 s, easing; announcements through the shared announcer; `onChange`) in `Apps/projectM-iOS/Coordinators/KenBurnsCoordinator.swift`
- [ ] MED-007-T07 [US2] `Apps/projectM-iOS/Coordinators/AppCoordinator+KenBurns.swift`: `applyKenBurns()` sets the photo layer's movement, duration (slide dwell while the slideshow is active) and Reduce Motion; called from `refreshPhotoContent`, the slideshow tick, `systemReduceMotionChanged`, the coordinator's `onChange` and Photo visual creation (small edits in `AppCoordinator.swift`, `AppCoordinator+Slideshow.swift`); `PhotoVisualHost` exposes nothing new (the layer is `host.photo`)
- [ ] MED-007-T08 [US2] `KenBurnsSection` (switch, Movement picker, Custom start/end sliders through `.accessibleParameter`, Duration stepper, Easing picker, Reduce Motion note) in `Apps/projectM-iOS/Views/KenBurnsSection.swift`, added to `mediaSections` in `Apps/projectM-iOS/Views/SettingsView.swift`
- [ ] MED-007-T09 [US2] UI test `Apps/projectM-iOS/UITests/KenBurnsUITests.swift`: Settings, Ken Burns on, Zoom out chosen, the summary reads it (< 30 s; MED-007-S5)

## Phase 5: User Story 3 - Slideshow and scenes (P2)

- [ ] MED-007-T10 [P] [US3] `SceneKenBurns` and `SceneAsset.photoKenBurns` (optional `kenBurns` field of a `photo` asset, malformed → nil) in `Packages/SceneFormat/Sources/SceneFormat/SceneKenBurns.swift`; tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneKenBurnsTests.swift` (round trip through encode/decode, malformed values, other kinds ignored; MED-007-S3)
- [ ] MED-007-T11 [US3] Scene paths: `SceneInputs.kenBurns`, `SceneSlideshowRestore.kenBurns`, `SceneSlideshowBridge.photoAsset(photoID:slideshow:kenBurns:)` and `restore(in:)`; capture in `SceneAutosaveCapture.swift`, `ShowSceneSnapshot.swift`, `AppCoordinator.swift`, `AppCoordinator+Show.swift`; restore through one helper `restorePhotoMotion(_:)` at every `slideshow.restore` call site (`AppCoordinator.swift`, `AppCoordinator+Show.swift`, `AppCoordinator+SceneHistory.swift`)
- [ ] MED-007-T12 [US3] App tests `Apps/projectM-iOS/Tests/KenBurnsAppTests.swift`: store round trip and clamping, scene capture/restore (absent → off), slideshow dwell (Time seconds, Beats with and without a grid), the photo layer receives the movement and Reduce Motion

## Phase 6: User Story 4 - Reduce Motion (P2)

- [ ] MED-007-T13 [US4] Reduce Motion end to end: `testReduceMotionHoldsTheStartRectangle` in `Packages/Compositor/Tests/CompositorTests/KenBurnsLayerTests.swift` (every frame equals the start frame; one render, then reuse) and `testReduceMotionReachesThePhotoLayer` in `Apps/projectM-iOS/Tests/KenBurnsAppTests.swift` (`systemReduceMotionChanged` sets the layer's `reduceMotion`) (MED-007-R7, S4)

## Phase 7: Polish & cross-cutting

- [ ] MED-007-T14 The new key in `Apps/projectM-iOS/Coordinators/AppSettings.swift` (`allKeys`), `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` (included keys), `scripts/run_device_tests.py` (`ALLOWED_KEYS`), `Apps/projectM-iOS/Tests/SettingsTests.swift` (store-written keys); run `LibraryBackupAppTests`, `SettingsTests` and the LibraryBackup package tests
- [ ] MED-007-T15 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), the SceneFormat suite including the QA-004 meta-test (`SceneMigrationMatrixMetaTests`), Linux shape of Compositor and SceneFormat (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), privacy manifest and network symbols on the built app, type-check budget, PosterBoard count; delete the simulator and derived data
- [ ] MED-007-T16 {device} On D1: a photo with Zoom in over 10 s moves smoothly and holds; a slideshow restarts the movement at each slide; Reduce Motion stops it

## Dependencies

T01 → T02 → T03 → T04 → T05; T06 → T07 → T08 → T09; T10 [P] after T02; T11 after T06 and T10 → T12; T14, T15 last.
US2 depends on US1's layer API; US3 on US2's coordinator.

## Parallel Example

T03 and T10 (different packages) can be written together after T02.

## Implementation Strategy

MVP = Phases 1-3 (the model and the GPU acceptance); then the Settings UI, scenes, polish.
