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
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination '<iOS 27.2 simulator>'
```

Expected: all pass. UI tests use the StoreKit test configuration (`Apps/projectM-iOS/Store/projectM-iOS.storekit`).

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

Automated by `scripts/run_device_tests.py` (prepared 2026-11-10) and the app's AutomationRunner
(`PROJECTM_AUTORUN` modes `sc101`, `sc102`, `sc104`, `entitlement` and `privacy`). Connect and
unlock the device, then run:

```bash
python3 scripts/run_device_tests.py devices          # D1-D3 connected and paired?
python3 scripts/run_device_tests.py build            # Release + PROJECTM_AUTOMATION, your signing team
python3 scripts/run_device_tests.py perf --device D1 --reinstall    # SC-101 (10 launches), SC-102, SC-104
python3 scripts/run_device_tests.py scroll --device D1              # SC-103: UI test on the device, 10 s per list
python3 scripts/run_device_tests.py size             # SC-108: App Thinning reports, 1.0 archive vs a new one
python3 scripts/run_device_tests.py summarize        # pass/fail per device against the spec targets
```

Repeat `perf` and `scroll` for D3; for D2, run only `scroll` (SC-101 and SC-102 name D1 and D3;
SC-104 names D1). Reports go to `docs/test-reports/exports/feature002/<D1|D2|D3>/`. Then record
them in `docs/test-reports/performance.md`.

Limits:
- SC-102 times the in-memory search only, not the list redraw.
- SC-103 runs the Debug build that UI tests use. Its frame meter counts display-link callbacks
  against refresh slots.
- `--simulator <UDID> --app <Debug .app>` rehearses any step on a simulator. Those results go to
  `exports/feature002/sim/`, which is gitignored, and are never evidence.

## Scenario E — Release

StoreKit sandbox purchase on a device (T239), with the in-app purchase created in App Store Connect
first (T242):

```bash
python3 scripts/run_device_tests.py entitlement --device D1
```

The script stops for each step a person must do:
1. Buy in the purchase sheet with the sandbox account.
2. The script relaunches the app on its own, which checks that the unlock is read back from
   StoreKit.
3. Turn on Airplane Mode for the offline relaunch.
4. The script reinstalls the app; then tap Restore Purchases.

After each step it records whether the app is unlocked, whether a Cream of the Crop preset plays,
and that no unlock flag is stored.

Privacy review (T241; feature 001 T108 with the new key):

```bash
python3 scripts/run_device_tests.py privacy --device D1
```

This installs the app fresh and runs a scripted session (In-App Playback, Next, a favorite, both
settings, a scope). It then lists the whole app container and the stored UserDefaults keys and
checks them against FR-065 and FR-123. Run `entitlement` first on the same install to cover "with a
purchase", using `privacy --no-install`.

The simulator rehearsal found one key that iOS writes, not the app: StoreKit's
`SKTransactionUpdatesLastChecked`, a timestamp. The check reports it as a note.

`docs/privacy-policy.md`, `docs/release/app-privacy.md` and `docs/release/store-copy.md` are
updated (T240). Signing and accounts stay manual.

