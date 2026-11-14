# Tasks: MED-010 Logo Overlay

**Input**: `specs/131-med-010-logo-overlay/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MED-010-S1 to S7). Budgets (owner rule 7): unit tests about 1-2 s
(≤ 10 s), package suite under 1 minute, UI test under 30 s. `{device}` tasks are the final device
stage and stay open until a person runs them on D1.

## Phase 1: Setup

- [ ] MED-010-T01 Run `xcodegen generate`, initialize the preset submodules if missing, create the simulator "MED10 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run (owner rule 5)

## Phase 2: Foundational (blocks every story)

- [ ] MED-010-T02 [P] `LogoCorner` and `LogoPlacement` (corner default `bottomRight`; size "0.05…0.5, default 0.15"; margin "0…0.2, default 0.04"; opacity "0…1, default 1"; anchor 0…1, non-finite → 0.5; lenient JSON; `rect(logoWidth:logoHeight:outputWidth:outputHeight:)` per research D5) in `Packages/Compositor/Sources/ImageLayer/LogoPlacement.swift` (contract C1)
- [ ] MED-010-T03 [P] `PremultipliedLinear` (sRGB byte → linear table, float ↔ half bits, `texels(_:)` giving (linear(c)·a, a) half bits, alpha 0 → all zero) in `Packages/Compositor/Sources/ImageLayer/PremultipliedLinear.swift` (contract C2)
- [ ] MED-010-T04 [P] `ImageOutputFormat` and `ImageSanitizer.sanitize(… format:)` (`.png` always writes PNG) in `Packages/Compositor/Sources/ImageLayer/ImageSanitizer.swift`; `LogoImport.limits` (10 MB, 16,777,216 pixels, 1024 px) and `LogoImport.message(for:)` in `Packages/Compositor/Sources/ImageLayer/LogoPlacement.swift`; `LayerKind.logo` in `ImageLayerKind.swift` (contract C4)
- [ ] MED-010-T05 `LogoLayerSource` (Metal: background load with `LogoImport.limits`, `rgba16Float` mipmapped premultiplied texture, quad at the placement rectangle, × opacity, `.notReady` without content, CMP-013 still dependencies, state callback, counters) in `Packages/Compositor/Sources/ImageLayer/LogoLayerSource.swift` (contract C3)
- [ ] MED-010-T06 Plain-Swift tests `LogoPlacementTests.swift` (every corner at 390 × 844 and 844 × 390 within 1 px, S4; wide and tall logos; clamping; JSON round trip and garbage → default) and `PremultipliedLinearTests.swift` (half conversion exactness on representative values, premultiplication, alpha 0) in `Packages/Compositor/Tests/CompositorTests/`; run also in the Linux shape
- [ ] MED-010-T07 Metal tests `Packages/Compositor/Tests/CompositorTests/LogoLayerTests.swift`: **the compositing acceptance** (S2): fixture PNG (64 × 64, horizontal alpha gradient 0…255, a fully transparent block, a coloured logo) through the sanitizer and `LogoLayerSource` over an opaque `SolidLayer` backdrop: every pixel equals premultiplied "over" in linear light within 2/255, the transparent block equals the backdrop within 1/255, no partial-alpha pixel darker than both backdrop and logo; the same at a quarter size (mipmapped, no fringe); opacity 0.6 scales; opacity change re-renders once, unchanged frames reuse (CMP-013); no content → transparent fallback; `ImageImportTests` case: `.png` format keeps an opaque picture lossless

## Phase 3: User Story 1 - Put my logo on the visuals (P1) — MVP

**Independent test**: import the fixture through `LogoStore`: the stored copy's alpha equals the original within 1/255 (S1); the logo layer is the top layer of the compositor visuals.

- [ ] MED-010-T08 [US1] `LogoStore` (`settings.logo.id`, `settings.logo.placement`; `stage` with logo limits and PNG; `importLogo`; `adopt`; `makeCurrent` releasing the previous logo keeping photo, slides and the new logo; `remove`; `protectedIDs`) in `Apps/projectM-iOS/Coordinators/LogoStore.swift`; `PhotoStore.makeCurrent`/`remove` and `SlideshowStore.release` keep `LogoStore.protectedIDs` (MED-010-R2, R3; contract C7)
- [ ] MED-010-T09 [US1] `LogoCoordinator` (imports from Photos/Files off the main actor, Remove, notices, announcements, placement setters persisted, `attach(to:)` creating a `LogoLayerSource` per compositor and pushing content/placement to every live layer, `layersDrawn` probe) in `Apps/projectM-iOS/Coordinators/LogoCoordinator.swift`, and `Compositor.attachLogo(_:)` (top `.logo` entry through `apply`) in the same file (contract C8; research D4)
- [ ] MED-010-T10 [US1] `AppCoordinator` wiring: `let logo: LogoCoordinator`, announcer (kind `library`), `logo.attach(to:)` in the Photo, Video, Text and Camera prepare functions, in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (+ a small `AppCoordinator+Logo.swift`) (MED-010-R5)
- [ ] MED-010-T11 [US1] Keys `settings.logo.id`, `settings.logo.placement` in `AppSettings.allKeys` (`Apps/projectM-iOS/Coordinators/AppSettings.swift`) and `ALLOWED_KEYS` (`scripts/run_device_tests.py`); `SettingsTests` FR-065 exclusion list (MED-010-R9)
- [ ] MED-010-T12 [US1] DEBUG seed `-uitestSeedLogo` (fixture logo through the real import path) in `Apps/projectM-iOS/Debug/UITestLogoFixture.swift` and probe `logoProbe` ("drawn=<n>") in `Apps/projectM-iOS/Views/VisualizerView.swift` (MED-010-R14)
- [ ] MED-010-T13 [US1] App tests `Apps/projectM-iOS/Tests/LogoStoreTests.swift`: **the import acceptance** (S1: alpha within 1/255, transparent region 0, PNG on disk); opaque JPEG input stored as PNG; over 10 MB and over 4096 × 4096 refused with the logo notice; same logo twice → one payload, a logo equal to the photo shares it, Remove Photo and a new photo keep the logo, Remove Logo keeps the photo (S5); relaunch keeps id and placement
- [ ] MED-010-T14 [US1] UI test `Apps/projectM-iOS/UITests/LogoOverlayUITests.swift` (`-uitestSeedLogo`, Text visual): `logoProbe` reports drawn > 0 (S7; under 30 s)

## Phase 4: User Story 2 - Place and fade the logo (P1)

**Independent test**: corner, size, margin and opacity setters persist and reach the live layer; the rectangle follows the rule (package tests T06/T07).

- [ ] MED-010-T15 [US2] `LogoSection` (preview, Choose from Photos, Choose from Files, Remove Logo, corner picker, size/margin/opacity sliders with `.accessibleParameter`, help naming the four visuals, notice) in `Apps/projectM-iOS/Views/LogoSection.swift`, mounted in `SettingsView.mediaSections` (`Apps/projectM-iOS/Views/SettingsView.swift`) (MED-010-R12)
- [ ] MED-010-T16 [US2] App test in `LogoStoreTests.swift`: coordinator placement setters persist (new coordinator on the same defaults) and update an attached layer's placement

## Phase 5: User Story 3 - Scenes, archives and backups (P2)

**Independent test**: scene archive round trip into a fresh sandbox (S3); backup includes and erase removes the keys (S6).

- [ ] MED-010-T17 [US3] Scene asset `logo` (`SceneAssetKind.logo(storeID:)`, decode/encode, `SceneAsset.logoPlacement`, `SceneDocument.logo`, validation: invalid ID error, missing picture `missingAsset`, never `unusedAsset`; repair title "Logo") in `Packages/SceneFormat/Sources/SceneFormat/SceneLogo.swift` and the switch sites; tests `Packages/SceneFormat/Tests/SceneFormatTests/SceneLogoTests.swift` (contract C5)
- [ ] MED-010-T18 [US3] Archive type `logo` (`png`, one, 4 files, photo limit; `mediaAssets`, remapping) in `Packages/SceneArchive/Sources/SceneArchive/SceneArchiveFormat.swift`, `SceneStoreRemapping.swift`, with reader/writer tests in `Packages/SceneArchive/Tests/SceneArchiveTests/` (contract C6)
- [ ] MED-010-T19 [US3] Backup and erase: `settings.logo.id` and `settings.logo.placement` in `LibrarySettingsPolicy.includedKeys` and erased with `.media` (not `.settings`) in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`, `LibraryErasePolicy.swift`, with package test assertions (MED-010-R9)
- [ ] MED-010-T20 [US3] Scene capture and restore: `SceneInputs.logo`, the `logo` asset in `SceneAutosaveCapture.document`, `SceneRestoredValues.logo`, `ShowLook`/`ShowSceneApply` logo, applied at launch restore, Reopen and cues when the picture resolves (not by undo) in `SceneAutosaveCapture.swift`, `ShowSceneSnapshot.swift`, `AppCoordinator.swift`, `AppCoordinator+Show.swift` (MED-010-R10)
- [ ] MED-010-T21 [US3] `SceneArchiveService`: export the logo file; import stages with a staging `LogoStore`, adopts, makes current with the scene's placement after photo and video; plan lists it (`Apps/projectM-iOS/Coordinators/SceneArchiveService.swift`) (MED-010-R11)
- [ ] MED-010-T22 [US3] App tests `Apps/projectM-iOS/Tests/LogoArchiveTests.swift`: **the export acceptance** (S3: export with the logo, import into a fresh sandbox, alpha within 1/255, placement equal); importing it twice keeps one payload; a scene capture records the logo and a restore applies it; backup policy includes and erase removes the keys (S6)

## Phase 6: Polish & cross-cutting

- [ ] MED-010-T23 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; long-body warnings flags on the changed files; Linux shape of Compositor and SceneFormat pure parts
- [ ] MED-010-T24 App tests (`projectM-iOSTests`), `PhotoLayerUITests` and `LogoOverlayUITests` on the own simulator; PosterBoard count after; delete the simulator; report `docs/test-reports/logo-overlay.md`; spec status Implemented
- [ ] MED-010-T25 {device} On D1: a transparent PNG from the real Photos picker and one from Files appear over the Photo visual with clean edges in each corner (MED-010-S8)

## Dependencies

- T02-T04 → T05 → T07; T02-T03 → T06.
- US1 (T08-T14) needs T02-T05. US2 needs US1's coordinator. US3: T17-T19 are independent of US1 (packages); T20-T22 need T08-T09 and T17-T18.
- Polish after all stories.

## Parallel examples

- T02, T03, T04 in parallel (different files); T17, T18, T19 in parallel with US1 app work.

## Implementation strategy

MVP = Phases 1-3 (the logo imported with alpha and drawn on the compositor visuals). Then placement
UI (US2), then scenes/archives/backups (US3), then checks and the report.
