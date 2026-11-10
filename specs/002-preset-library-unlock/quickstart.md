# Quickstart: Full Preset Library Unlock (feature 002)

## Setup (macOS)

```bash
git submodule update --init --recursive              # includes Vendor/presets/*
python3 scripts/build_preset_index.py --check        # committed index matches the pinned packs
xcodegen generate
```

## Automated checks

```bash
swift test --package-path Packages/PresetLibrary     # index, tree, scopes, stepping, random, search (also on Linux)
python3 scripts/test_scripts.py                      # includes build_preset_index tests
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme ProjectMiOS -destination '<iOS 27.2 simulator>'
```

Expected: all pass. UI tests use the StoreKit test configuration (`Apps/ProjectMiOS/Store/ProjectMiOS.storekit`).

## Scenario A — Free library (US1)

Fresh install, no purchase: the browser home shows Included (28), four locked packs with totals,
All A-Z. Next/Previous/Random stay in Included and match release 1.0's order. A 1.0 favorite still
plays (FR-104, SC-107).

## Scenario B — Purchase, restore, refund (US2)

Simulator with the StoreKit configuration: tap a locked preset → sheet with price, packs, Buy,
Restore; Buy → everything unlocks within 1 s, scope Cream of the Crop (SC-105). Relaunch with
networking off → still unlocked. Refund in the StoreKit transaction manager → locks; the playing
preset continues; scope Included (FR-109). Ask to Buy → "Waiting for approval", unlocks on approval.

## Scenario C — Large library (US3)

Unlocked: open Cream of the Crop › Fractal › Nested Spiral, play, Next at the end wraps, Random
stays inside; search "geiss" → grouped, capped at 200 with a refine prompt.

## Scenario D — Device measurements (D1-D3; device only)

Index load (signpost from launch to library ready, SC-101), search latency (SC-102), scrolling
(Instruments, SC-103), preset switch (feature 001 SC-007 automation over packs, SC-104), installed
size versus 1.0 (SC-108). Record in `docs/test-reports/performance.md`.

## Scenario E — Release

StoreKit sandbox purchase on a device; privacy review re-run (feature 001 T108) with the new key;
`docs/privacy-policy.md`, `docs/release/app-privacy.md` and `docs/release/store-copy.md` updated;
the owner creates the in-app purchase product in App Store Connect (signing and accounts stay manual).
