# Implementation Plan: PRE-004 Preset Color Facets

**Branch**: `feature/pre-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/213-pre-004-color-facets/spec.md`

## Summary

Dominant colours are learned from PRE-001 thumbnails as rows decode them, kept in a versioned JSON index in
Caches, and offered as colour chips that narrow the browser together with PRE-003 tags, Favorites and search.

- **PresetLibrary** (Foundation only, Linux-tested): `PresetColorFamily` (11 named families),
  `PresetColorPalette` (fixed 32 × 18 sample grid, integer HSL rules, ≥ 12% share, top 3), `PresetColorIndex`
  (schema 1, palette 1, open-time repair), `PresetColorStore` (actor: record, coalesced save, invalidate,
  retainOnly, snapshot) and `PresetColorFilter` (AND matching, counts). `PresetColorPNG` (ImageIO and
  CoreGraphics, behind `#if canImport(ImageIO)`) decodes a PNG to RGBA8 for the palette.
- **App**: `PresetThumbnailModel` computes colours on its existing detached decode task when the preset's mirror
  entry is not for the current thumbnail ID, updates a main-actor mirror and records them in the store; launch
  collection prunes and loads the mirror; PRE-002 invalidation drops a changed preset's colours.
  `PresetCoordinator+Colors` holds the selection (in memory), counts, `filteredListing` and the search
  narrowing; `PresetColorChipRow` sits under the tag chips; `TaggedPresetList` shows tags AND colours.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new (ImageIO and CoreGraphics on Apple platforms only).

**Storage**: `Library/Caches/PresetColors/colors.json` (excluded from backup; FILE-009 "Caches"; FILE-010 Clear
Caches). No UserDefaults key.

**Testing**: XCTest. PresetLibrary on the host (Linux in CI for the Foundation parts); app unit tests and one UI
test on the private simulator "PRE4 iPhone 17" (iOS 27.2). Injected sleep for the coalesced save.

**Target Platform**: iOS/iPadOS 26+; package also macOS 15 and Linux.

**Performance Goals**: 576 classified samples per thumbnail (< 5 ms on the host in Debug); at most one index
write per second; nothing at launch beyond the existing utility-priority collection.

**Constraints**: type-check budget; small edits to shared files (`PresetBrowserView`, `PresetCoordinator`).

**Scale/Scope**: up to 12,847 entries of about 80 bytes (about 1 MB at full coverage; typically a few hundred).

## Constitution Check

- I Public APIs only: Foundation, ImageIO, CoreGraphics, SwiftUI. Pass.
- VI Modular boundaries: colour maths, index and filter in PresetLibrary (Foundation only); decoding guarded. Pass.
- VII Real-time audio safety: no audio path touched; work at utility priority off the main actor. Pass.
- Privacy/local-first: a local cache file; no network, no new stored setting. Pass.
- X Evidence-based quality: deterministic fixtures; no device claim. Pass.

Post-design re-check: unchanged, pass. No ADR: no constitution or project default is overridden.

## Project Structure

```text
Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorFamily.swift       (new)
Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorPalette.swift      (new)
Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorIndex.swift        (new)
Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorStore.swift        (new)
Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorFilter.swift       (new)
Packages/PresetLibrary/Sources/PresetLibrary/Colors/PresetColorPNG.swift          (new, Apple only)
Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrary.swift                  (alphabetical listing of IDs)
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetColorFacetTests.swift       (new)
Packages/PresetLibrary/Tests/PresetLibraryTests/ThumbnailFixtures/colors-*.json   (new fixtures)
Apps/projectM-iOS/Coordinators/PresetThumbnailModel.swift                         (colours on decode, mirror)
Apps/projectM-iOS/Coordinators/AppCoordinator+Thumbnails.swift                    (store creation)
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift                            (state, collection hook)
Apps/projectM-iOS/Coordinators/PresetCoordinator+Colors.swift                     (new)
Apps/projectM-iOS/Views/PresetColorChips.swift                                    (new)
Apps/projectM-iOS/Views/PresetBrowserView.swift, PresetTagChips.swift             (small)
Apps/projectM-iOS/Tests/PresetColorFacetAppTests.swift                            (new)
Apps/projectM-iOS/UITests/PresetColorFacetUITests.swift                           (new)
```

**Structure Decision**: everything that decides a colour lives in PresetLibrary so the acceptance runs on Linux;
the app only decodes (through the package's guarded helper) and wires the mirror to the chips.
