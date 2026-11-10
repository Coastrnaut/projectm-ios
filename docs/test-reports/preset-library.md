# Feature 002: preset library report

Measurements and checks for the full preset library (`specs/002-preset-library-unlock/`).
Simulator and Mac results here are not device evidence; the device measurements are T238.

## Bundle growth (T214, SC-108), 2026-11-10

Built by the "Preset library (feature 002)" build phase (`scripts/build_preset_index.py`) into
ProjectMiOS.app (Debug, iOS 27.2 simulator build, Xcode 27.2). Nothing generated is committed.

| File | Size |
|------|------|
| `PresetArchive.bin` (12,913 pack presets, raw deflate, 64 per chunk) | 13,700,160 bytes |
| `PresetIndex.json` (12,941 records) | 4,862,511 bytes |
| `PresetPacks.json` | 34,739 bytes |
| `PresetTextures/` (108 images) | 7,776 KiB on disk |
| **Total added** | **about 26.6 MB** |

The SC-108 limit is 40 MB over release 1.0. The installed-size comparison on a device is T238.

## App checks on the simulator, 2026-11-10

`ProjectMiOSTests` on the iOS 27.2 simulator: 43 tests, 0 failures. They include:

- `PresetTests.testBundledIncludedScopeMatchesRelease1_0`: loads the real bundled index. Before
  purchase the scope has exactly the 28 Included presets, in the order release 1.0's
  `PresetRepository` gives (SC-107). The index has more than 12,000 presets.
- `LibraryStoreTests` (7, `SKTestSession` with `Store/ProjectMiOS.storekit`):
  - purchase unlocks, and a relaunch reads the unlock back from StoreKit;
  - cancel, failure and Ask to Buy unlock nothing, and a later approval unlocks;
  - a refund locks again;
  - restore unlocks;
  - no UserDefaults key is written.

The host app does not touch StoreKit while it is hosting unit tests (`XCTestConfigurationFilePath`
is set). Otherwise its launch-time product request runs before the test's `SKTestSession` exists,
and every product request then returns nothing.
