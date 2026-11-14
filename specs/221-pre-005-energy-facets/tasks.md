# Tasks: PRE-005 Preset Energy Facets

**Input**: Design documents from `specs/221-pre-005-energy-facets/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/energy-facets.md, quickstart.md

Tests are requested by the roadmap acceptance ("Classification is stable for fixed preset seed and fixture").

## Phase 1: Setup

- [ ] PRE-005-T01 Create the private simulator "PRE5 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run

## Phase 2: Foundational

- [ ] PRE-005-T02 [P] `PresetEnergy` and `PresetMotionScore` (research D3, contract C2: grid 32 × 18, `Y = (77R + 150G + 29B) >> 8`, score in thousandths, "Calm < 4,000; Moderate < 16,000; Energetic ≥ 16,000") in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetEnergy.swift and PresetMotionScore.swift
- [ ] PRE-005-T03 [P] `PresetMotionPNG` (D4, C3: tEXt `projectM-motion`, "<version>:<score>", CRC-32, before IEND) in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionPNG.swift
- [ ] PRE-005-T04 `PresetMotionIndex` with open-time repair and `PresetMotionStore` (D5, C4: schema 1, score version 1, entries dropped "when score < 0 or thumbnailID empty", coalesced 1 s save) in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetMotionIndex.swift and PresetMotionStore.swift
- [ ] PRE-005-T05 `PresetEnergyFilter` (D6: OR within classes, counts, chips) in Packages/PresetLibrary/Sources/PresetLibrary/Motion/PresetEnergyFilter.swift
- [ ] PRE-005-T06 Engine clock and samples (D1, D2, C1): `ProjectMEngine.setFrameTime` in Packages/ProjectMBridge/Sources/ProjectMBridge/include/PMBridge.h and PMBridge.mm; `drawSamples` with a default in Packages/Rendering/Sources/Rendering/VisualizerRenderer.swift; the runner pins `n / 60` s and reads back requested frames in Packages/ANGLERendering/Sources/ANGLERendering/PresetThumbnailRunner.swift

## Phase 3: User Story 2 - The same preset always gets the same class (P1)

**Independent test**: fixtures score to pinned values twice; the real engine draws identical samples twice.

- [ ] PRE-005-T07 [US2] Package acceptance (S1 determinism part): static, slow drift and seeded fast-noise fixtures → Calm, Moderate, Energetic; scored twice → bit-identical and equal to pinned values; PNG field round trip and foreign versions ignored, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetEnergyFacetTests.swift
- [ ] PRE-005-T08 [US2] Engine determinism (S3): a time-driven preset drawn twice with `drawSamples` gives two samples, identical bytes and the same score, in Packages/ANGLERendering/Tests/ANGLERenderingTests/PresetThumbnailRunnerTests.swift

## Phase 4: User Story 1 - Find calm or energetic presets (P1) MVP

**Independent test**: the energy filter returns exactly the fixture presets of the chosen classes.

- [ ] PRE-005-T09 [US1] Filter acceptance (S1 filter part): for each class and for Calm + Energetic, `matching(any:)` returns exactly the fixture presets; counts and chips, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetEnergyFacetTests.swift
- [ ] PRE-005-T10 [US1] Scores on the thumbnail path: `RendererThumbnailRenderer` asks for samples, scores and embeds; fixture renderer embeds a byte-derived score; the model learns scores on its decode task (mirror, store, launch load and prune, PRE-002 invalidation), in Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift, AppCoordinator+Thumbnails.swift and PresetCoordinator.swift
- [ ] PRE-005-T11 [US1] `PresetCoordinator+Energy` (selection, counts, join into `filterMatches`, announcements, empty text) in Apps/projectM-iOS/Coordinators/PresetCoordinator+Energy.swift and PresetCoordinator+Colors.swift
- [ ] PRE-005-T12 [US1] `PresetEnergyChipRow` and browser placement in Apps/projectM-iOS/Views/PresetEnergyChips.swift and PresetBrowserView.swift
- [ ] PRE-005-T13 [US1] App acceptance (S4): a fixture thumbnail records its score once; the energy filter lists it; combined with a colour narrows; invalidation drops it; a chip toggle announces on the search lane, in Apps/projectM-iOS/Tests/PresetEnergyFacetAppTests.swift
- [ ] PRE-005-T14 [US1] UI test (S5, under 30 s) with `-uitestThumbnailFixture` in Apps/projectM-iOS/UITests/PresetEnergyFacetUITests.swift

## Phase 5: User Story 3 - A damaged or old index rebuilds itself (P2)

- [ ] PRE-005-T15 [US3] Migration fixtures motion-v0.json, motion-v99.json, motion-corrupt.json, motion-score-v0.json, motion-v1.json in Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/ and tests (S2) plus store coalescing, in PresetEnergyFacetTests.swift

## Phase 6: Polish

- [ ] PRE-005-T16 Type-check budget on touched app files; repo checks (compliance, docs, motion, permission catalog, status events, script tests); privacy manifest and network symbols on the Debug app; `LibraryBackupAppTests`; spec status; delete the simulator and derived data; PosterBoard count after
- [ ] PRE-005-T17 {device} Tune the provisional thresholds with a device sweep of real thumbnails (score distribution on D1); a threshold change needs no data migration

## Dependencies

T02-T05 → T07, T09, T15; T06 → T08, T10; T10 → T11 → T12 → T13, T14. US2 and US1 share the foundation; US3 depends only on T04.
Parallel: T02, T03 and T06 touch different packages.
MVP: Phases 2-4.
