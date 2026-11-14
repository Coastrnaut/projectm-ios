# Tasks: PRE-004 Preset Color Facets

**Input**: Design documents from `specs/213-pre-004-color-facets/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/color-facets.md, quickstart.md

Tests are requested by the roadmap acceptance ("Palette filter matches seeded thumbnail color fixtures") and its
verification ("unit + simulator + fixture migrations").

## Phase 1: Setup

- [ ] PRE-004-T01 Create the private simulator "PRE4 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run

## Phase 2: Foundational

- [ ] PRE-004-T02 `PresetColorFamily` and `PresetColorPalette` (research D2-D3, contract C1) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorFamily.swift and PresetColorPalette.swift
- [ ] PRE-004-T03 `PresetColorIndex` with open-time repair (D4, C2) and `PresetColorStore` (coalesced save, invalidate, retainOnly; D5-D6, C3) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorIndex.swift and PresetColorStore.swift
- [ ] PRE-004-T04 `PresetColorFilter` (C4) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorFilter.swift; `PresetLibrary.alphabeticalListing(_:)` in Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrary.swift; Apple-only `PresetColorPNG` (D8) in Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorPNG.swift

## Phase 3: User Story 1 - Find presets by colour (P1) MVP

**Independent test**: seeded synthetic thumbnails map to families; the filter returns exactly the matching fixtures.

- [ ] PRE-004-T05 [US1] Package acceptance (S1): solid red, two-tone yellow/blue, grey gradient, noisy green fixtures → expected families; for every family the filter returns exactly the fixture presets including it; AND of two families; counts; PNG round trip on Apple platforms, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetColorFacetTests.swift
- [ ] PRE-004-T06 [US1] `PresetCoordinator+Colors` (selection, counts over listed presets, `filteredListing`, search narrowing, announcements on the search lane, scope per R11) in Apps/projectM-iOS/Coordinators/PresetCoordinator+Colors.swift and state in Apps/projectM-iOS/Coordinators/PresetCoordinator.swift
- [ ] PRE-004-T07 [US1] `PresetColorChipRow` (swatch, name, count, Selected trait, Clear, coverage text) in Apps/projectM-iOS/Views/PresetColorChips.swift; browser wiring in Apps/projectM-iOS/Views/PresetBrowserView.swift and Apps/projectM-iOS/Views/PresetTagChips.swift

## Phase 4: User Story 2 - Colours appear as I browse (P1)

**Independent test**: a thumbnail made through the real model records colours once; the coordinator lists it.

- [ ] PRE-004-T08 [US2] Colours on the model's decode task, mirror, store recording, launch load and prune, PRE-002 invalidation in Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift, Apps/projectM-iOS/Coordinators/AppCoordinator+Thumbnails.swift and Apps/projectM-iOS/Coordinators/PresetCoordinator.swift
- [ ] PRE-004-T09 [US2] App acceptance (S3) in Apps/projectM-iOS/Tests/PresetColorFacetAppTests.swift: a fixture thumbnail records colours once; `filteredListing` for its colour lists it, combined with a tag narrows; invalidation drops its colours
- [ ] PRE-004-T10 [US2] UI test (S4) in Apps/projectM-iOS/UITests/PresetColorFacetUITests.swift: with `-uitestThumbnailFixture`, chips appear after a folder's thumbnails, a chip lists only matching presets, Clear restores the home (under 30 s)

## Phase 5: User Story 3 - A damaged or old index rebuilds itself (P2)

- [ ] PRE-004-T11 [US3] Migration fixtures colors-v0.json, colors-v99.json, colors-corrupt.json, colors-palette-v0.json, colors-v1.json in Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/ and tests (S2) in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetColorFacetTests.swift (rebuilt and rewritten; current kept, unknown colours dropped; store coalesces saves and prunes)

## Phase 6: Polish

- [ ] PRE-004-T12 Type-check budget on touched app files; repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; spec status; delete the simulator and derived data; PosterBoard count after
