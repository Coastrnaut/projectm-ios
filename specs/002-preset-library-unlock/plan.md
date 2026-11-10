# Implementation Plan: Full Preset Library Unlock

**Branch**: `002-preset-library-unlock` (work lands on `main`) | **Date**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-preset-library-unlock/spec.md`

## Summary

Bundle the four projectM preset packs and the texture pack as pinned git submodules, index them at
build time into one de-duplicated library (12,943 presets: 28 free, 12,915 locked), and replace the
launch-time folder scan with that index. A new Foundation-only package, `PresetLibrary`, holds the
index model, scopes and search; the app adds a hierarchical preset browser with search, scoped
Next/Previous/Random, and a StoreKit 2 non-consumable that unlocks everything but the 28 Included
presets. The engine gets the texture pack on its texture search path. A new ADR records the
license basis for selling access (spec Clarifications).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2, ADR-0002); Python 3 for the build-time index
script; Objective-C++ for one new bridge call.

**Primary Dependencies**: StoreKit 2 (system framework, public API); the existing engine
(`Vendor/projectM`), ANGLE renderer, `Rendering` and `ProjectMBridge` packages; five new pinned
git submodules under `Vendor/presets/` (research R-21).

**Storage**: Bundled read-only files (preset packs as folder references, `PresetIndex.json`,
`PresetPacks.json`, `PresetBlocklist.json`); `UserDefaults` for favorites, last preset and the new
`settings.presetScope` (spec FR-123); purchase state only from StoreKit (FR-110).

**Testing**: XCTest. `PresetLibrary` unit tests run on Linux and macOS (no UIKit). App unit tests
and UI tests on the iOS 27.2 simulator with a StoreKit test configuration (`.storekit`,
`SKTestSession`). Python tests for the index script in `scripts/test_scripts.py`. Device
measurements on D1-D3 per feature 001's rules.

**Target Platform**: iOS/iPadOS 26.0+ (unchanged).

**Project Type**: Mobile app (existing projectM-iOS target) plus Swift packages.

**Performance Goals**: index decode and library build under 150 ms on D3 (SC-101); search under
50 ms per keystroke (SC-102); lists at display rate (SC-103); preset switch within feature 001
SC-007 (SC-104).

**Constraints**: no network except StoreKit (FR-122); no stored unlock flag (FR-110); persistence
limited to FR-123's list; installed size growth ≤ 40 MB (SC-108); ids of the 28 Included presets
unchanged (FR-104).

**Scale/Scope**: 12,943 indexed presets across 5 sources, 183 cream-of-the-crop subcategories,
about 2,400 authors; index JSON about 2 MB.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|-----------|-------|--------|
| I. Public Apple APIs only | StoreKit 2 and `UserDefaults` only; no private API; `check_compliance.py` unchanged | Pass |
| II-III. Capture | Not affected | n/a |
| IV. Truthful source labeling | Not affected | n/a |
| V. No universal-capture claims | Store copy changes add no capture claims (T110 rules still apply) | Pass |
| VI. Modular boundaries | New `PresetLibrary` package (Foundation only) holds index, scopes, search; StoreKit stays in the app behind `EntitlementProviding`; the engine learns only a texture path through the bridge | Pass |
| VII. Real-time audio safety | No audio-path change | n/a |
| VIII. Upstream ProjectM fidelity | Engine unchanged; texture paths via the documented `projectm_set_texture_search_paths` | Pass |
| IX. Pinned dependencies and license review | Five submodules pinned to exact commits in ADR-0004; per-pack license review and the selling decision in new ADR-0007; blocklist for author requests | Pass (ADR-0007 required before release) |
| X. Evidence-based quality | Unit tests for every deterministic rule; StoreKit flows tested with a test configuration; device measurements for SC-101-SC-104 and SC-108; privacy review re-run (feature 001 T108) | Pass (device work pending devices) |

Post-design re-check (after Phase 1): unchanged; no violations, Complexity Tracking empty.

## Project Structure

### Documentation (this feature)

```text
specs/002-preset-library-unlock/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── preset-index.schema.json
│   ├── preset-library.md
│   └── store.md
├── checklists/
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
Vendor/presets/                         # git submodules, pinned (ADR-0004, research R-21)
├── cream-of-the-crop/
├── projectm-classic/
├── milkdrop-original/
├── en-d/
└── milkdrop-texture-pack/

Packages/PresetLibrary/                 # NEW: Foundation only, Linux-testable
├── Package.swift
├── Sources/PresetLibrary/
│   ├── PresetIndex.swift               # decoded index + pack metadata (contracts/preset-index.schema.json)
│   ├── PresetLibrary.swift             # hierarchy, lookup, lock state, exclusions
│   ├── PresetScope.swift               # scopes, next/previous/random over playable presets
│   └── PresetSearch.swift              # name/author search, grouping, cap
└── Tests/PresetLibraryTests/

Packages/ProjectMBridge/                # + setTextureSearchPaths:, loadPresetData: (PMBridge.h/.mm)
Packages/Rendering/                     # VisualizerRenderer gains texture paths and prewarm(_:); Preset stays the playable unit
Packages/ANGLERendering/                # + PresetPrewarmer.swift: warms upcoming presets on a background context (R-31, SC-104)

Apps/projectM-iOS/
├── Coordinators/PresetCoordinator.swift    # scopes, entitlement-aware playback, planned Random pick (R-31)
├── Coordinators/FavoritesStore.swift       # + settings.presetScope
├── Store/LibraryStore.swift                # NEW: StoreKit 2 entitlement + purchase (EntitlementProviding)
├── Store/projectM-iOS.storekit              # NEW: StoreKit test configuration
├── Views/PresetBrowserView.swift           # library home, folders, search
├── Views/PurchaseSheet.swift               # NEW
├── Views/ControlsOverlay.swift             # scope line under the preset name
└── Resources/
    ├── PresetBlocklist.json                # author-request removals (hashes), committed
    └── PresetExclusions.txt                # load-sweep failures (ids), committed
    (PresetIndex.json, PresetPacks.json, PresetArchive.bin and PresetTextures/ are generated into
    the app bundle at build time by scripts/build_preset_index.py; research R-30)

scripts/build_preset_index.py               # NEW: build phase: index, packs, archive, textures
Apps/RendererLab/LabModel.swift             # + RL_MODE=loadsweep (load-only, shardable)
docs/adr/0007-preset-library-licensing.md   # NEW
```

**Structure Decision**: one new package (`PresetLibrary`) for all deterministic library logic, so it
runs in the Linux CI job; StoreKit and SwiftUI stay in the app target. Preset packs enter only as
submodules and are bundled as folder references; generated index files are committed like the
Licenses manifest, with a `--check` in CI.

## Phases

1. **Content and index**: submodules, `build_preset_index.py` (dedup by git blob hash with the
   Included set first, `.milk` only, blocklist, exclusions from the load sweep), generated files,
   ADR-0004 rows, ADR-0007.
2. **PresetLibrary package**: index decoding, hierarchy, scopes, search, lock state, tests
   (13,000-entry synthetic index for performance).
3. **Engine and app wiring**: texture search path; `PresetRepository` replaced by the index for the
   app; favorites id stability; scope persistence.
4. **Store**: `LibraryStore` (StoreKit 2), `.storekit` test configuration, purchase sheet,
   entitlement updates, refund handling.
5. **Browser UI**: library home, folders, All A-Z with section index, search, locks, scope line,
   VoiceOver.
6. **Sweep, measurements, release docs**: load-only sweep and exclusions, device measurements,
   Licenses per pack, privacy policy, App Privacy, store copy, privacy review.

## Complexity Tracking

No constitution violations.
