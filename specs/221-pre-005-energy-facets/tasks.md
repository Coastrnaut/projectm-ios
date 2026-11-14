# Tasks: PRE-005 Preset Energy Facets

**Input**: Design documents from `specs/221-pre-005-energy-facets/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/energy-facets.md, quickstart.md

Tests are requested by the roadmap acceptance ("Classification is stable for fixed preset seed and fixture").

## Phase 1: Setup

- [X] PRE-005-T01 Create the private simulator "PRE5 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run — Verified 2026-11-14: simulator 58E48E86 created on iOS 27.2; PosterBoard reports 26 before

## Phase 2: Foundational

- [X] PRE-005-T02 [P] `PresetEnergy` and `PresetMotionScore` (research D3, contract C2: grid 32 × 18, `Y = (77R + 150G + 29B) >> 8`, score in thousandths, "Calm < 4,000; Moderate < 16,000; Energetic ≥ 16,000") in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetEnergy.swift and PresetMotionScore.swift — Verified 2026-11-14: `testFixedFixturesClassifyStablyWithPinnedScores` (thresholds 3,999/4,000/16,000, invalid input); `swift test --package-path Packages/PresetLibrary` (329 tests, 0 failures, 48.9 s); `--filter PresetEnergyFacetTests` (5 tests, 0.07 s)
- [X] PRE-005-T03 [P] `PresetMotionPNG` (D4, C3: tEXt `projectM-motion`, "<version>:<score>", CRC-32, before IEND) in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionPNG.swift — Verified 2026-11-14: `testTheScoreTravelsInThePNGField` (CRC-32 of IEND = 0xAE426082, replace not duplicate, foreign version ignored, ImageIO still decodes a tagged PNG); `swift test --package-path Packages/PresetLibrary` (329 tests, 0 failures, 48.9 s); `--filter PresetEnergyFacetTests` (5 tests, 0.07 s)
- [X] PRE-005-T04 `PresetMotionIndex` with open-time repair and `PresetMotionStore` (D5, C4: schema 1, score version 1, entries dropped "when score < 0 or thumbnailID empty", coalesced 1 s save) in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionIndex.swift and PresetMotionStore.swift — Verified 2026-11-14: `testStoreCoalescesSavesInvalidatesAndPrunes`, `testOldUnknownAndCorruptIndexesAreRebuiltAndCurrentIsKept`; `swift test --package-path Packages/PresetLibrary` (329 tests, 0 failures, 48.9 s); `--filter PresetEnergyFacetTests` (5 tests, 0.07 s)
- [X] PRE-005-T05 `PresetEnergyFilter` (D6: OR within classes, counts, chips) in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetEnergyFilter.swift — Verified 2026-11-14: `testTheEnergyFilterMatchesExactlyTheFixturePresets`; `swift test --package-path Packages/PresetLibrary` (329 tests, 0 failures, 48.9 s); `--filter PresetEnergyFacetTests` (5 tests, 0.07 s)
- [X] PRE-005-T06 Engine clock and samples (D1, D2, C1): `ProjectMEngine.setFrameTime` in Packages/ProjectMBridge/Sources/ProjectMBridge/include/PMBridge.h and PMBridge.mm; `drawSamples` with a default in Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift; the runner pins `n / 60` s and reads back requested frames in Packages/ANGLERendering/Sources/ANGLERendering/PresetThumbnailRunner.swift — Verified 2026-11-14: ANGLERendering `xcodebuild test -only-testing:ANGLERenderingTests/PresetThumbnailRunnerTests` on "PRE5 iPhone 17" (2 tests, 0 failures; the existing PRE-001 test still passes); app build-for-testing succeeds

## Phase 3: User Story 2 - The same preset always gets the same class (P1)

**Independent test**: fixtures score to pinned values twice; the real engine draws identical samples twice.

- [X] PRE-005-T07 [US2] Package acceptance (S1 determinism part): static, slow drift and seeded fast-noise fixtures → Calm, Moderate, Energetic; scored twice → bit-identical and equal to pinned values; PNG field round trip and foreign versions ignored, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetEnergyFacetTests.swift — Verified 2026-11-14: `testFixedFixturesClassifyStablyWithPinnedScores`: static 0 (Calm), drift 7,875 (Moderate), seeded noise 86,832 (Energetic), second run bit-identical; another seed stays Energetic
- [X] PRE-005-T08 [US2] Engine determinism (S3): a time-driven preset drawn twice with `drawSamples` gives two samples, identical bytes and the same score, in Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetThumbnailRunnerTests.swift — Verified 2026-11-14: `PresetThumbnailRunnerTests.testSamplesWithAPinnedClockAreIdenticalOnASecondDrawing` (7.4 s on the simulator; simulator, not device evidence)

## Phase 4: User Story 1 - Find calm or energetic presets (P1) MVP

**Independent test**: the energy filter returns exactly the fixture presets of the chosen classes.

- [X] PRE-005-T09 [US1] Filter acceptance (S1 filter part): for each class and for Calm + Energetic, `matching(any:)` returns exactly the fixture presets; counts and chips, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetEnergyFacetTests.swift — Verified 2026-11-14: `testTheEnergyFilterMatchesExactlyTheFixturePresets` (each class exactly its fixture; Calm + Energetic = static + noise)
- [X] PRE-005-T10 [US1] Scores on the thumbnail path: `RendererThumbnailRenderer` asks for samples, scores and embeds; fixture renderer embeds a byte-derived score; the model learns scores on its decode task (mirror, store, launch load and prune, PRE-002 invalidation), in Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift, AppCoordinator+Thumbnails.swift and PresetCoordinator.swift — Verified 2026-11-14: app tests on "PRE5 iPhone 17" (iOS 27.2): `PresetEnergyFacetAppTests` (scores through `RendererThumbnailRenderer` → PNG field → cache → decode; relaunch reads back with no new drawing; PRE-002 invalidation drops); `PresetThumbnailModelTests` (6), `PresetThumbnailInvalidationAppTests` (2), `PresetColorFacetAppTests` (1) pass
- [X] PRE-005-T11 [US1] `PresetCoordinator+Energy` (selection, counts, join into `filterMatches`, announcements on the search lane, empty text, scope stays tags or All per R12) in Apps/projectM-iOS/Coordinators/PresetCoordinator+Energy.swift and PresetCoordinator+Colors.swift — Verified 2026-11-14: app tests on "PRE5 iPhone 17" (iOS 27.2): `PresetEnergyFacetAppTests` (OR, AND with colours, search narrowing, announcements on the search lane, empty text, scope All)
- [X] PRE-005-T12 [US1] `PresetEnergyChipRow` and browser placement in Apps/projectM-iOS/Views/PresetEnergyChips.swift and PresetBrowserView.swift — Verified 2026-11-14: app tests on "PRE5 iPhone 17" (iOS 27.2): `PresetEnergyFacetUITests` taps a chip named "… motion" and Clear; `PresetColorFacetUITests` still passes; build-for-testing with the type-check flags shows no long bodies or expressions in touched files
- [X] PRE-005-T13 [US1] App acceptance (S4): a fixture thumbnail records its score once; the energy filter lists it; combined with a colour narrows; invalidation drops it; a chip toggle announces on the search lane; `filteredScope` stays All with only energy selected (R12), in Apps/projectM-iOS/Tests/PresetEnergyFacetAppTests.swift — Verified 2026-11-14: app tests on "PRE5 iPhone 17" (iOS 27.2): `PresetEnergyFacetAppTests.testScoresFromThumbnailSamplesFilterTheBrowser` (1 test, 3.3 s)
- [X] PRE-005-T14 [US1] UI test (S5, under 30 s) with `-uitestThumbnailFixture` in Apps/projectM-iOS/UITests/PresetEnergyFacetUITests.swift — Verified 2026-11-14: app tests on "PRE5 iPhone 17" (iOS 27.2): `PresetEnergyFacetUITests.testMotionChipNarrowsTheHomeAndClearRestoresIt` (11.6 s)

## Phase 5: User Story 3 - A damaged or old index rebuilds itself (P2)

- [X] PRE-005-T15 [US3] Migration fixtures motion-v0.json, motion-v99.json, motion-corrupt.json, motion-score-v0.json, motion-v1.json in Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/ and tests (S2) plus store coalescing, in PresetEnergyFacetTests.swift — Verified 2026-11-14: `testOldUnknownAndCorruptIndexesAreRebuiltAndCurrentIsKept` (v0, v99, corrupt, score version 0 rebuilt and rewritten; v1 kept, 2 invalid entries dropped)

## Phase 6: Polish

- [X] PRE-005-T16 Record the extra drawing cost honestly (two read-backs; simulator only, not device evidence); type-check budget on touched app files; repo checks (compliance, docs, motion, permission catalog, status events, script tests); privacy manifest and network symbols on the Debug app; `LibraryBackupAppTests`; spec status; delete the simulator and derived data; PosterBoard count after — Verified 2026-11-14: cost: two extra `PMANGLEFinish` + read-backs per drawing (32 × 18 test drawing with samples: 7.4 s for two drawings on the simulator, dominated by shader compiles; no device measurement); type-check flags clean in touched files; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 164 tests OK; check_privacy_manifest and check_network_symbols OK on the Debug app; `LibraryBackupAppTests` (5) pass (no new UserDefaults key); PosterBoard reports 26 before and after; simulator and derived data deleted
- [ ] PRE-005-T17 {device} Tune the provisional thresholds with a device sweep of real thumbnails (score distribution on D1); a threshold change needs no data migration

## Dependencies

T02-T05 → T07, T09, T15; T06 → T08, T10; T10 → T11 → T12 → T13, T14. US2 and US1 share the foundation; US3 depends only on T04.
Parallel: T02, T03 and T06 touch different packages.
MVP: Phases 2-4.

## Analysis (speckit-analyze, 2026-11-14)

- Coverage: R1, R2, R3 → T02, T06, T07, T08; R4 → T03, T10; R5-R7 → T04, T15; R8-R10 → T11, T12, T13, T14; R11 → T04,
  T10, T13 (Clear Caches needs no code: the folder is inside `Library/Caches`, which FILE-010 empties); R12 → T11,
  T13; R13 → T02-T05 and the Linux-shaped package build. S1 → T07, T09; S2 → T15; S3 → T08; S4 → T13; S5 → T14.
- Fixes applied: R12 had no test (now asserted in T13); the drawing's added cost had no owner (now T16).
- Constitution: VIII satisfied by the public `projectm_set_frame_time`; X by pinned fixtures and the provisional
  thresholds left as `{device}` T17. No ADR needed.
