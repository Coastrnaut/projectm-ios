# Feature 002: preset library report

Measurements and checks for the full preset library (`specs/002-preset-library-unlock/`).
Simulator and Mac results here are not device evidence; the device measurements are T238.

## Bundle growth (T214, SC-108), 2026-11-10

Built by the "Preset library (feature 002)" build phase (`scripts/build_preset_index.py`) into
projectM-iOS.app (Debug, iOS 27.2 simulator build, Xcode 27.2). Nothing generated is committed.

| File | Size |
|------|------|
| `PresetArchive.bin` (12,913 pack presets before the T237 exclusions, raw deflate, 64 per chunk) | 13,700,160 bytes |
| `PresetIndex.json` (12,941 records) | 4,862,511 bytes |
| `PresetPacks.json` | 34,739 bytes |
| `PresetTextures/` (108 images) | 7,776 KiB on disk |
| **Total added** | **about 26.6 MB** |

After the 94 exclusions (below) the archive is 13,527,590 bytes. The SC-108 limit is 40 MB over
release 1.0. The installed-size comparison on a device is T238.

## App checks on the simulator, 2026-11-10

`projectM-iOSTests` on the iOS 27.2 simulator: 43 tests, 0 failures. They include:

- `PresetTests.testBundledIncludedScopeMatchesRelease1_0`: loads the real bundled index. Before
  purchase the scope has exactly the 28 Included presets, in the order release 1.0's
  `PresetRepository` gives (SC-107). The index has more than 12,000 presets.
- `LibraryStoreTests` (7, `SKTestSession` with `Store/projectM-iOS.storekit`):
  - purchase unlocks, and a relaunch reads the unlock back from StoreKit;
  - cancel, failure and Ask to Buy unlock nothing, and a later approval unlocks;
  - a refund locks again;
  - restore unlocks;
  - no UserDefaults key is written.

The host app does not touch StoreKit while it is hosting unit tests (`XCTestConfigurationFilePath`
is set). Otherwise its launch-time product request runs before the test's `SKTestSession` exists,
and every product request then returns nothing.

## UI tests on the simulator, 2026-11-10

`projectM-iOSUITests` on the iOS 27.2 simulator: 25 tests pass.

- `PresetLibraryUITests` (5):
  - the home shows its rows and counts, with locks before purchase;
  - drill-down works, and a locked tap opens the purchase sheet;
  - search results are grouped by pack and capped;
  - before purchase, Next and Random play only Included presets;
  - unlocked: Fractal › Nested Spiral (179) wraps with Next and Previous, and Random stays inside it.
- `PurchaseUITests` (3, SKTestSession):
  - the sheet shows the price and the packs;
  - Buy unlocks the library and switches the scope to "Cream of the Crop · 9795";
  - a failed purchase shows "Purchase failed" and unlocks nothing.
- Feature 001's `testPresetBrowser` was updated for the library home.

`testFirstAndSecondLaunchAndTheMicrophoneExplainer` first failed because this simulator had
already granted the microphone permission. It passed after
`simctl privacy <device> reset microphone`.

## Load sweep (T236, T237), 2026-11-10

RendererLab `-mode loadsweep` with the ANGLE backend on the iOS 27.2 simulator (iPhone 18 Pro), in
four shards (`RL_SHARD=1/4` to `4/4`). Each preset in the index was built with `--no-exclusions`
and loaded once, with no render wait. The run took about 18 minutes. The reports are in the
simulator's RendererLab Documents folder and are not committed.

| Shard | Presets | Failed | Median load | Max load |
|-------|---------|--------|-------------|----------|
| 1/4 | 3,236 | 33 | 37.2 ms | 398 ms |
| 2/4 | 3,236 | 19 | 36.5 ms | 1,444 ms |
| 3/4 | 3,236 | 15 | 34.8 ms | 287 ms |
| 4/4 | 3,233 | 27 | 2.6 ms | 507 ms |
| **Total** | **12,941** | **94** | | |

- None of the 28 Included presets failed.
- Failures by pack: Cream of the Crop 67, projectM Classic 15, Milkdrop Original 10, En D 2.
- Every failure is the engine's own code compiler rejecting the preset's equations, for example
  "Could not compile per-frame code: syntax error". There were no crashes.
- Shard 4's much lower median suggests the app stopped drawing during that shard, so those loads
  did not include first-frame work. The sweep checks loading only. A preset that loads but
  misbehaves when drawn is not caught; it is removed from the session when it fails (FR-118).

The 94 ids are in `Apps/projectM-iOS/Resources/PresetExclusions.txt` (FR-103).

The sweep also exposed a script bug. An excluded preset's identical copy in a later pack came back
under its own id, giving 12,851 presets instead of 12,847. `build_preset_index.py` now marks an
excluded preset's content as seen, and a script test covers this.

The index is now **12,847 presets: the 28 Included plus 12,819 in packs.**

| Pack | Presets |
|------|---------|
| Cream of the Crop | 9,728 |
| projectM Classic | 2,569 |
| Milkdrop Original | 487 |
| En D | 35 |

The store copy, the StoreKit description, the license entries and the UI tests use these counts.

## Update, 2026-11-10 (version 1.1 (2), device automation)

`projectM-iOSTests` now has 44 tests and `projectM-iOSUITests` 27, all passing on an erased iOS 27.2
simulator, with each test limited to 3 minutes.

- **StoreKit tests:** `LibraryStoreTests` now has 8 tests. A real Ask to Buy purchase in StoreKit's
  local test environment asks for an Apple Account sign-in, which hung unattended runs. The pending
  outcome is now tested through `LibraryStore.handle(.pending)`, with the approval delivered later
  by `SKTestSession.buyProduct`. A cancelled purchase has its own test. The real Ask to Buy sheet is
  part of the device sandbox run (T239).
- **New UI tests:** `PresetScrollPerformanceUITests` (SC-103). On the simulator, which is not
  evidence: All A-Z had 98.1% of frames on time and the largest folder 98.6%.
- **Device automation:** `scripts/run_device_tests.py` (quickstart Scenarios D and E). A rehearsal
  on the simulator, also not evidence:
  - SC-102: max 10.6 ms (search only);
  - SC-104: 100% of switches under 1 s;
  - SC-101: 212 ms, over the 150 ms target, so the device result matters;
  - privacy: zero violations, plus one key that StoreKit writes itself.
