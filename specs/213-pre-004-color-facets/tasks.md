# Tasks: PRE-004 Preset Color Facets

**Input**: Design documents from `specs/213-pre-004-color-facets/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/color-facets.md, quickstart.md

Tests are requested by the roadmap acceptance ("Palette filter matches seeded thumbnail color fixtures") and its
verification ("unit + simulator + fixture migrations").

## Phase 1: Setup

- [X] PRE-004-T01 Create the private simulator "PRE4 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run — Verified 2026-11-14: simulator F5FB30F2 created on iOS 27.2; PosterBoard reports 26 before

## Phase 2: Foundational

- [X] PRE-004-T02 `PresetColorFamily` and `PresetColorPalette` (research D2-D3, contract C1) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorFamily.swift and PresetColorPalette.swift — Verified 2026-11-14: `PresetColorFacetTests.testClassificationRulesAndInvalidInput`; `swift test --package-path Packages/PresetLibrary` (324 tests, 0 failures, 29.0 s)
- [X] PRE-004-T03 `PresetColorIndex` with open-time repair (D4, C2) and `PresetColorStore` (coalesced save, invalidate, retainOnly; D5-D6, C3) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorIndex.swift and PresetColorStore.swift — Verified 2026-11-14: `testStoreCoalescesSavesInvalidatesAndPrunes`, `testOldUnknownAndCorruptIndexesAreRebuiltAndCurrentIsKept`; `swift test --package-path Packages/PresetLibrary` (324 tests, 0 failures, 29.0 s)
- [X] PRE-004-T04 `PresetColorFilter` (C4) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorFilter.swift; `PresetLibrary.alphabeticalListing(_:)` in Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrary.swift; Apple-only `PresetColorPNG` (D8) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorPNG.swift — Verified 2026-11-14: `testSeededFixturesMapToTheirFamiliesAndTheFilterMatchesExactly`, `testPNGDecodeKeepsTheFamilies`; `swift test --package-path Packages/PresetLibrary` (324 tests, 0 failures, 29.0 s)

## Phase 3: User Story 1 - Find presets by colour (P1) MVP

**Independent test**: seeded synthetic thumbnails map to families; the filter returns exactly the matching fixtures.

- [X] PRE-004-T05 [US1] Package acceptance (S1): solid red, two-tone yellow/blue, grey gradient, noisy green fixtures → expected families; for every family the filter returns exactly the fixture presets including it; AND of two families; counts; PNG round trip on Apple platforms, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetColorFacetTests.swift — Verified 2026-11-14: `swift test --filter PresetColorFacetTests` (5 tests, 0.08 s), acceptance `testSeededFixturesMapToTheirFamiliesAndTheFilterMatchesExactly`
- [ ] PRE-004-T06 [US1] `PresetCoordinator+Colors` (selection, counts over listed presets, `filteredListing`, search narrowing, announcements on the search lane, scope per R11) in Apps/projectM-iOS/Coordinators/PresetCoordinator+Colors.swift and state in Apps/projectM-iOS/Coordinators/PresetCoordinator.swift
- [ ] PRE-004-T07 [US1] `PresetColorChipRow` (swatch, name, count, Selected trait, Clear, coverage text) in Apps/projectM-iOS/Views/PresetColorChips.swift; browser wiring in Apps/projectM-iOS/Views/PresetBrowserView.swift and Apps/projectM-iOS/Views/PresetTagChips.swift

## Phase 4: User Story 2 - Colours appear as I browse (P1)

**Independent test**: a thumbnail made through the real model records colours once; the coordinator lists it.

- [ ] PRE-004-T08 [US2] Colours on the model's decode task, mirror, store recording, launch load and prune, PRE-002 invalidation in Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift, Apps/projectM-iOS/Coordinators/AppCoordinator+Thumbnails.swift and Apps/projectM-iOS/Coordinators/PresetCoordinator.swift
- [ ] PRE-004-T09 [US2] App acceptance (S3) in Apps/projectM-iOS/Tests/PresetColorFacetAppTests.swift: a fixture thumbnail records colours once; `filteredListing` for its colour lists it, combined with a tag narrows; invalidation drops its colours; a chip toggle announces the count on the search lane (R9)
- [ ] PRE-004-T10 [US2] UI test (S4) in Apps/projectM-iOS/UITests/PresetColorFacetUITests.swift: with `-uitestThumbnailFixture`, chips appear after a folder's thumbnails, a chip lists only matching presets, Clear restores the home (under 30 s)

## Phase 5: User Story 3 - A damaged or old index rebuilds itself (P2)

- [X] PRE-004-T11 [US3] Migration fixtures colors-v0.json, colors-v99.json, colors-corrupt.json, colors-palette-v0.json, colors-v1.json in Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/ and tests (S2) in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetColorFacetTests.swift (rebuilt and rewritten; current kept, unknown colours dropped; store coalesces saves and prunes) — Verified 2026-11-14: `testOldUnknownAndCorruptIndexesAreRebuiltAndCurrentIsKept` (v0, v99, corrupt, palette 0 rebuilt and rewritten; v1 kept, "teal" dropped)

## Phase 6: Polish

- [ ] PRE-004-T12 Record S5 from the package palette test's duration (no wall-clock assertion); type-check budget on touched app files; repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; spec status; delete the simulator and derived data; PosterBoard count after

## Analysis (speckit-analyze, 2026-11-14)

- Coverage: R1-R3 → T02, T05, T08; R4-R6 → T03, T11; R7, R9 → T07, T09, T10; R8, R11 → T06, T09; R10 → T03, T08,
  T09 (Clear Caches needs no code: the folder is inside `Library/Caches`, which FILE-010 empties); R12 → T04 and the
  Linux-shaped package build. S1 → T05; S2 → T11; S3 → T09; S4 → T10; S5 → T12.
- Fixes applied: S5 was unowned (now T12, recorded from a test duration, never asserted on the clock); R9's
  announcement had no test (now in T09).
- No constitution conflicts; no ADR needed.
