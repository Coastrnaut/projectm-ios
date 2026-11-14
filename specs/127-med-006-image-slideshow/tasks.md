# Tasks: MED-006 Image Slideshow

**Input**: `specs/127-med-006-image-slideshow/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MED-006-S1 to S8). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1.

## Phase 1: Setup

- [ ] MED-006-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MED6 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] MED-006-T02 [P] `SlideshowSettings`, `SlideshowMode`, `SlideshowBeatGrid`, `SlideshowSafetyFloor` and `SlideshowSchedule` (plain Swift; "≤ 20 (`maximumSlides`), no duplicates", seconds "2…60 … default 5; clamped", beats "one of 1, 2, 4, 8, 16 … default 4; other values read as 4"; floor (4 − f) s; contract C1, C2) in `Packages/Compositor/Sources/ImageLayer/Slideshow.swift`
- [ ] MED-006-T03 [P] `ImageLayerSource.preload(_:)` and synchronous adoption of a prepared texture when `content` is set to that URL (contract C3) in `Packages/Compositor/Sources/ImageLayer/ImageLayerSource.swift`
- [ ] MED-006-T04 Package tests `Packages/Compositor/Tests/CompositorTests/SlideshowTests.swift` (plain Swift, Linux shape): settings sanitizing and JSON; **the acceptance** schedule with five slides on an injected clock: Time 5 s order over two cycles at exact 5 s steps (MED-006-S1), Beats every 2 on an injected 120 BPM grid changes on beats 2, 4, 6… (MED-006-S2); nil grid falls back to Time (S4); floor at 240 BPM every 1 beat for f = 3, 2, 1 (S5); steps over 1 s add nothing; a timing change restarts without a change; one slide never changes
- [ ] MED-006-T05 Metal tests `Packages/Compositor/Tests/CompositorTests/SlideshowLayerTests.swift`: five solid-colour PNG fixtures cycled through `ImageLayerSource` + compositor with preload: each change renders the layer exactly once, the frame after the change shows the new colour in full (a cut, no transparent frame, MED-006-S6, R8), later frames reuse the picture

## Phase 3: User Story 1 - Cycle several pictures on a timer (P1) — MVP

**Independent test**: five fixture slides in Time mode follow the saved order on an injected clock; relaunch (a new store on the same defaults) keeps order and mode.

- [ ] MED-006-T06 [US1] `SlideshowStore` (`settings.photo.slideshow` JSON; drops IDs that do not resolve; `stage` through `PhotoStore.stage`; `release`; `protectedIDs`) in `Apps/projectM-iOS/Coordinators/SlideshowStore.swift`, and `PhotoStore.makeCurrent`, `remove`, `trim` keeping `protectedIDs` in `Apps/projectM-iOS/Coordinators/PhotoStore.swift` (MED-006-R1, R10, R11)
- [ ] MED-006-T07 [US1] `SlideshowCoordinator` (settings edits, imports of several files off the main actor with the 20 limit and notice, list edits keeping the shown picture, thumbnails, schedule tick → URL, preload URL, announcements) in `Apps/projectM-iOS/Coordinators/SlideshowCoordinator.swift` (contract C4)
- [ ] MED-006-T08 [US1] `PhotoVisualHost.beforeFrame` and `preload(_:)` in `Apps/projectM-iOS/Visuals/PhotoVisualHost.swift`; `AppCoordinator` wiring (create `slideshow`, content = current slide when active, `slideshowTick()` with `MonotonicClock`, safety floor from `settings.safetyClamp`, re-choose content on playback change; a slide's `.failed` layer state does not raise the photo notice while the slideshow is active (analyze E1, MED-006-R3); the slides stay inside the photo host's compositor, so `applyReduceFlashing` keeps the composite flash guard and the profile's envelope on every frame (analyze E4, R7)) in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] MED-006-T09 [US1] Key `settings.photo.slideshow` in `AppSettings.allKeys` (`Apps/projectM-iOS/Coordinators/AppSettings.swift`) and `ALLOWED_KEYS` (`scripts/run_device_tests.py`)
- [ ] MED-006-T10 [US1] DEBUG probe `slideshowProbe` ("<index> changes=<n>") in `Apps/projectM-iOS/Views/VisualizerView.swift` and seed `-uitestSeedPhoto slideshow5` (five 64 × 48 solid colours through the real slide import, Slideshow on, Time 2 s) in `Apps/projectM-iOS/Debug/UITestPhotoFixture.swift`
- [ ] MED-006-T11 [US1] App tests `Apps/projectM-iOS/Tests/SlideshowTests.swift`: store round trip and relaunch (S3 persistence), unresolved IDs dropped, coordinator ticks follow the saved order with an injected clock, edits keep the shown picture
- [ ] MED-006-T12 [US1] UI test `Apps/projectM-iOS/UITests/SlideshowUITests.swift` (`-uitestSeedPhoto slideshow5`, Photo visual): `slideshowProbe` index advances 0 → 1 → 2 in order with changes counting (MED-006-S8; under 30 s)

## Phase 4: User Story 2 - Change pictures on the beat (P1)

**Independent test**: an injected reliable grid changes slides on every Nth beat; an unreliable tempo uses the Time interval.

- [ ] MED-006-T13 [US2] Grid from the tempo in `AppCoordinator.slideshowTick()` (only `.manual`/`.stable` with period and anchor; static `SlideshowCoordinator.grid(snapshot:readout:)`), with app tests in `SlideshowTests.swift` for each readout (MED-006-R6, S4)

## Phase 5: User Story 3 - Arrange the slideshow (P2)

**Independent test**: reorder, remove and clear through the coordinator; removed references are released.

- [ ] MED-006-T14 [US3] `SlideshowSection` (Toggle, rows with thumbnails, swipe delete, Edit Order + `.onMove`, VoiceOver Move Up / Move Down / Delete, Add from Photos (multi), Add from Files (multi), Clear, mode Picker, seconds Slider with `.accessibleParameter`, beats Picker, footer; the seconds slider ends its undo coalescing on release like the video loop sliders (analyze E3, R12); small bodies, typed string steps, no animation) in `Apps/projectM-iOS/Views/SlideshowSection.swift`, mounted after the Photo section in `Apps/projectM-iOS/Views/SettingsView.swift` (MED-006-R13)
- [ ] MED-006-T15 [US3] App tests in `SlideshowTests.swift`: move, move up/down, remove (reference released, payload deleted when unshared), clear, the 20 limit, a new photo and Remove Photo release no slide; add, remove, move and clear announce through the injected announce closure wired to the shared announcer (kind `library`) (analyze E2, R13) (MED-006-S7, R2, R11)

## Phase 6: User Story 4 - Scenes and backups (P2)

- [ ] MED-006-T16 [P] [US4] `SceneSlideshow` and `SceneAsset.photoSlideshow` (contract C5) in `Packages/SceneFormat/Sources/SceneFormat/SceneSlideshow.swift` with tests `Packages/SceneFormat/Tests/SceneFormatTests/SceneSlideshowTests.swift`
- [ ] MED-006-T17 [US4] Scene carriers: `SceneInputs.slideshow`, `SceneRestoredValues.slideshow`, `ShowLook.slideshow`, `ShowSceneApply.slideshow`; capture writes the photo asset with the field; restore and undo and cue apply via `SlideshowCoordinator.restore` in `Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift`, `ShowSceneSnapshot.swift`, `AppCoordinator+SceneHistory.swift`, `AppCoordinator+Show.swift`, `AppCoordinator.swift`; round-trip test (capture, change order and mode, restore → saved order and mode; S3) in `SlideshowTests.swift`
- [ ] MED-006-T18 [P] [US4] Backup and erase policy: `settings.photo.slideshow` in `LibrarySettingsPolicy.includedKeys`, `LibraryErasePolicy` media keys and owned keys, package tests updated, in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` and `LibraryErasePolicy.swift`; app test: backup contents include the key and the slide photos, erase plan removes them (S7)

## Phase 7: Polish & cross-cutting

- [ ] MED-006-T19 Linux shape: `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter SlideshowTests`
- [ ] MED-006-T20 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`, `check_privacy_manifest.py` on the built Debug app; long-body flags report nothing in the new files
- [ ] MED-006-T21 App unit tests (projectM-iOSTests) and UI tests PhotoLayerUITests and SlideshowUITests on the own simulator; PosterBoard count after; delete the simulator; report `docs/test-reports/image-slideshow.md`; spec status updated
- [ ] MED-006-T22 `{device}` On D1 (MED-006-S9): five pictures chosen at once in the real Photos picker and two from Files cycle in order in Time and Beats (tapped tempo) modes; relaunch keeps order and mode

## Dependencies

- T01 → everything. T02 → T04, T06, T07. T03 → T05, T08. T06 → T07 → T08 → T10 → T12. T09 with T06. T13 after T08. T14 after T07. T16 → T17. T18 after T06's key name. T19-T21 after all code; T22 after release to the device stage.
- Stories: US1 (T06-T12) is the MVP; US2 (T13) and US3 (T14-T15) depend on T07/T08; US4 (T16-T18) on T07.

## Parallel examples

- T02 and T03 (different files), T16 and T18 (different packages).

## Implementation strategy

MVP = Phases 1-3 (model, preload, store, coordinator, host wiring, probe). Then beats, the Settings
section, scenes and backups, then polish. One commit per complete change.
