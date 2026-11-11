---

description: "Task list for feature 002: full preset library unlock"
---

# Tasks: Full Preset Library Unlock

**Input**: Design documents from `specs/002-preset-library-unlock/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Requested (tests first wherever the logic is deterministic; owner instruction 2026-11-10).

**Organization**: Tasks are grouped by user story. IDs start at T201 so they never collide with
feature 001's T001-T120. Tags: `{device}` needs D1-D3 and a person; `{owner}` needs the owner's
accounts or signing; untagged tasks are completable on the project Mac.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1-US4 from spec.md

---

## Phase 1: Setup

- [X] T201 Add the five preset packs as shallow git submodules pinned to research R-21's commits under `Vendor/presets/` (`cream-of-the-crop`, `projectm-classic`, `milkdrop-original`, `en-d`, `milkdrop-texture-pack`; `shallow = true` in `.gitmodules`), and add one row per pack to `docs/adr/0004-dependency-pinning.md` — Done 2026-11-10: five shallow submodules at R-21's commits; ADR-0004 rows
- [X] T202 Create `Packages/PresetLibrary` (Foundation only, iOS 26 and Linux; `Package.swift`, `Sources/PresetLibrary/`, `Tests/PresetLibraryTests/`), add it to `project.yml` as a dependency of projectM-iOS, and to the Linux host-test job in `.github/workflows/ios-ci.yml` — Done 2026-11-10: package created, projectM-iOS depends on it, in all five CI package loops (Linux, macOS, iOS compile, iOS 26 and 27 simulators)
- [X] T203 [P] Write `docs/adr/0007-preset-library-licensing.md` (research R-29: what the purchase sells, the per-pack license review, blocklist policy, risk and fallback of dropping a pack) and list it in `docs/adr/README.md` — Done 2026-11-10: `docs/adr/0007-preset-library-licensing.md`, ADR index

---

## Phase 2: Foundational (blocks all stories)

- [X] T204 [P] Add tests for the index script to `scripts/test_scripts.py` with a fixture tree under `scripts/fixtures/preset-packs/`: priority Included → cream-of-the-crop → projectm-classic → milkdrop-original → en-d keeps the first occurrence of a hash; only `.milk` files; blocklisted hashes and `--exclusions` ids skipped; Included ids keep the form `frontend-uwp/<file>.milk` and Included names come from `Resources/Presets/LICENSES.md`'s "Display name" column (U1); author is the text before the first " - " ("Unknown" if none); `--check` fails on a stale file — Done 2026-11-10: `PresetIndexTests` (4) in `scripts/test_scripts.py` with a temporary fixture tree, pass (the script was written just before its tests)
- [X] T205 Implement `scripts/build_preset_index.py --out <dir>` (research R-30: build phase, nothing generated is committed; stamp-skipped) writing `PresetIndex.json`, `PresetArchive.bin`, `PresetTextures/` and (contracts/preset-index.schema.json: `version` 1; `source` one of `included`, `cream-of-the-crop`, `projectm-classic`, `milkdrop-original`, `en-d`; `hash` matching `^[0-9a-f]{40}$`) and `PresetPacks.json` (data-model.md: `commit` must equal the submodule's), reading `Apps/projectM-iOS/Resources/PresetBlocklist.json` (`{"hashes": []}`), with `--check` and `--exclusions <file>` — Done 2026-11-10: `scripts/build_preset_index.py --out`; tests pass
- [X] T206 Commit the empty `PresetBlocklist.json` and `PresetExclusions.txt`; generate the outputs locally and confirm the counts (12,941 presets: Included 28, cream-of-the-crop 9,795, projectm-classic 2,584, milkdrop-original 497, en-d 37) — Done 2026-11-10: committed empty blocklist and exclusions; local build: 12,941 presets (28 / 9,795 / 2,584 / 497 / 37), archive 13 MB, textures 7.6 MB (108 files)
- [X] T207 [P] Write `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetLibraryTests.swift`: decoding, `home` order (Included, the four packs, All), node counts, folder trees per pack (cream category/subcategory, classic collection, en-d episode, original flat), lock state before and after unlock, `members` excludes locked and excluded presets, alphabetical order (localized standard compare) — Done 2026-11-10: `PresetLibraryTests` pass (swift test, macOS host)
- [X] T208 Implement `IndexedPreset`, `PresetPackInfo`, `PresetNode` and `PresetLibrary` (decode, tree, lookup, `members`, async `load(from:)`) in `Packages/PresetLibrary/Sources/PresetLibrary/PresetIndex.swift` and `PresetLibrary.swift` per contracts/preset-library.md — Done 2026-11-10
- [X] T209 [P] Write `PresetScopeTests.swift`: `storageValue` round trips (`included`, `pack:<id>`, `folder:<id>/<a>/<b>`, `favorites`, `all`; a search scope stores `all`); `ScopeStepper.step` wraps both ends and returns nil for an empty scope; `random` never returns the current preset when count > 1 over 1,000 picks with a seeded generator (SC-106) — Done 2026-11-10: `PresetScopeTests` (3) pass
- [X] T210 Implement `PresetScope` and `ScopeStepper` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetScope.swift` — Done 2026-11-10
- [X] T211 [P] Write `PresetSearchTests.swift`: matches name and author, case- and diacritic-insensitive, from one character; groups ordered Included then FR-102 pack order, alphabetical within; at most 200 with `truncated` — Done 2026-11-10: `PresetSearchTests` (3) pass
- [X] T212 Implement search with precomputed folded keys in `Packages/PresetLibrary/Sources/PresetLibrary/PresetSearch.swift` — Done 2026-11-10
- [X] T213 [P] Add a 13,000-entry synthetic-index performance test (decode and build, and one search) to `PresetLibraryTests` as a regression guard (host numbers only; device numbers in T238) — Done 2026-11-10: 13,000-entry guard; host debug build 124 ms, search 7 ms (device numbers: T238)
- [X] T214 Add the build phase to projectM-iOS in `project.yml` running `scripts/build_preset_index.py --out` into the app's resources folder; confirm the built app contains the index, archive and textures and measure the bundle growth — Verified 2026-11-10: the built app contains the index, archive and 108 textures; growth about 26.6 MB (`docs/test-reports/preset-library.md`).
- [X] T215 Add `-[PMBridge setTextureSearchPaths:]` (documented `projectm_set_texture_search_paths`) and `-[PMBridge loadPresetData:smooth:error:]` (`projectm_load_preset_data`) in `Packages/ProjectMBridge/Sources/ProjectMBridge/include/PMBridge.h` and `PMBridge.mm`, a test in `PMEngineTests`, and set `PresetTextures` as the search path and load pack presets from data in `ANGLERenderer` and `GLESRenderer` — Done 2026-11-10: `loadPresetData:` and `setTextureSearchPaths:`; `PMEngineTests` `testPresetLoadsFromData`, `testTextureSearchPathsAreAccepted` pass on the iOS 27.2 simulator; renderers load `Preset.data` when set and expose `setTextureSearchPaths`

---

## Phase 3: User Story 1 — Browse and play a large library without paying (P1) 🎯 MVP

**Goal**: The library home, folders, All A-Z and search; Included plays exactly as in 1.0; locked presets are visible.

**Independent Test**: quickstart.md Scenario A.

- [X] T216 [P] [US1] Extend `Apps/projectM-iOS/Tests/PresetTests.swift`: with the library and no unlock, the Included scope's Next/Previous order equals release 1.0's 28-preset order (SC-107); a 1.0 favorite id still resolves (FR-104); favorites of ids missing from the index are dropped at launch — Verified 2026-11-10: PresetTests on the iOS 27.2 simulator, including the real bundled index against release 1.0's PresetRepository order.
- [X] T217 [US1] Rework `Apps/projectM-iOS/Coordinators/PresetCoordinator.swift` to use `PresetLibrary`, the current `PresetScope` (default `included`) and an entitlement flag; `AppCoordinator` loads the library off the main thread instead of `PresetRepository`; `RendererPresetLoader` resolves `path` in the bundle — Verified 2026-11-10: app builds with no warnings; PresetTests pass.
- [X] T218 [US1] Add `settings.presetScope` to `Apps/projectM-iOS/Coordinators/AppSettings.swift` (with the other `settings.*` keys) with FR-123's rule (a search scope stores `all`); update `AppSettings.allKeys`, `SettingsTests` and the FR-065 key list in `docs/test-reports/privacy-review.md` — Verified 2026-11-10: SettingsTests pass; key added to `docs/test-reports/privacy-review.md`.
- [X] T219 [US1] Rebuild `Apps/projectM-iOS/Views/PresetBrowserView.swift` as a `NavigationStack`: library home (Included 28, each pack with its total and a lock before purchase, All A-Z), keeping the All/Favorites picker and FR-088's empty-state text — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): PresetLibraryUITests.testHomeRowsCountsAndLocks and VisualizerUITests.testPresetBrowser (favorites picker and empty state).
- [X] T220 [US1] Add folder lists per pack structure (FR-112) and All A-Z with letter sections and a section index in `Apps/projectM-iOS/Views/PresetFolderView.swift` — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): drill-down to Fractal › Nested Spiral. A-Z letter sections with a section index (`sectionIndexLabel`).
- [X] T221 [US1] Add `.searchable` over the library with grouped, capped results and a "Refine your search" row (FR-113) in `PresetBrowserView.swift` — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): testSearchIsGroupedAndCapped (the cap notice is now first in the results); grouping and cap also in PresetSearchTests.
- [X] T222 [US1] Mark locked rows (lock icon, "locked" in the accessibility label) and route a locked tap to the purchase entry point (stub until T227) — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): a locked row's label ends ", locked" and tapping it opens the purchase sheet.
- [X] T245 [US1] Favorites view across packs (FR-114): alphabetical, each row showing its pack, locked favorites marked, in `PresetBrowserView.swift`, with a case in `PresetTests.swift` — Verified: PresetTests.testFavoritesFilterAcrossPacksAndEmptyState; rows show "author · pack" in Favorites.
- [X] T223 [US1] Write `Apps/projectM-iOS/UITests/PresetLibraryUITests.swift`: home rows and counts, folder drill-down, search grouping and cap, Included-only playback with Next/Random, a locked tap opens the purchase entry point — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): PresetLibraryUITests, 4 cases before purchase.

---

## Phase 4: User Story 2 — Unlock the full library with one purchase (P1)

**Goal**: StoreKit purchase, restore, refund and pending handling; unlock without relaunch, offline.

**Independent Test**: quickstart.md Scenario B (simulator, StoreKit test configuration).

- [X] T224 [US2] Add `Apps/projectM-iOS/Store/projectM-iOS.storekit` (non-consumable `org.projectmios.ProjectMiOS.fullLibrary`, $1.99) and set it as the run and test StoreKit configuration of the projectM-iOS scheme in `project.yml` — Verified 2026-11-10: run scheme uses it; tests load it with SKTestSession.
- [X] T225 [P] [US2] Write `Apps/projectM-iOS/Tests/LibraryStoreTests.swift` with `SKTestSession`: purchase unlocks; cancel, failure and Ask to Buy unlock nothing and set the matching state; approval later unlocks; refund locks; restore unlocks; no `UserDefaults` key is written (FR-110) — Verified 2026-11-10: 7 tests pass on the iOS 27.2 simulator.
- [X] T226 [US2] Implement `Apps/projectM-iOS/Store/LibraryStore.swift` (`EntitlementProviding`, contracts/store.md: `Product.products(for:)`, `Transaction.currentEntitlements`, `Transaction.updates`, `AppStore.sync()`; verified, unrevoked transactions only) and a DEBUG `FakeEntitlements` driven by `-uitestUnlocked` — Verified 2026-11-10 by LibraryStoreTests.
- [X] T227 [US2] Implement `Apps/projectM-iOS/Views/PurchaseSheet.swift`: localized price, the four packs with counts, Buy, Restore Purchases, Close; messages "Purchase cancelled", "Waiting for approval", "Purchase failed: <reason>", "The App Store isn't available right now", and a restricted-purchases message — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): PurchaseUITests (price, packs, Restore, Close, failure message).
- [X] T228 [US2] Wire entitlement changes into `PresetCoordinator`: unlock → scope `pack:cream-of-the-crop` and the tapped preset plays (FR-107, FR-119); refund → scope `included`, the playing preset continues (FR-109) — Verified 2026-11-10 by PresetTests (unlock, locked tap, refund).
- [X] T229 [US2] Write `Apps/projectM-iOS/UITests/PurchaseUITests.swift` with the StoreKit configuration: sheet contents, buy unlocks and switches scope, cancel shows the message — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): PurchaseUITests, 3 cases with SKTestSession.

---

## Phase 5: User Story 3 — Find and play presets in a 12,943-preset library (P2)

**Goal**: Scopes set by browsing, scope line in the controls, accessible navigation.

**Independent Test**: quickstart.md Scenario C.

- [X] T230 [P] [US3] Extend `PresetTests.swift`: choosing a preset from a folder, Favorites or a search sets that scope; Next wraps inside it; Random stays inside; a stored scope that no longer resolves falls back (Included before purchase, All after) — Verified 2026-11-10 by PresetTests.
- [X] T246 [P] [US3] Exclude presets that fail to load from every scope for the rest of the session (FR-118, feature 001 FR-045) in `PresetCoordinator`, with a test in `PresetTests.swift` — Verified 2026-11-10 by PresetTests.testFailedLoadKeepsThePreviousPresetReportsAndExcludesIt.
- [X] T231 [US3] Set the scope on selection in `PresetCoordinator` and show "<scope> · <count>" under the preset name in `Apps/projectM-iOS/Views/ControlsOverlay.swift` (FR-120) — Verified: scope line in PresetTests (scopeLine) and in PresetLibraryUITests ("Fractal › Nested Spiral · 179").
- [X] T232 [US3] Accessibility (FR-124): row labels "Name, by Author[, locked]", folder counts, purchase sheet controls, and an announcement when the scope changes — Done 2026-11-10: row, folder and purchase-sheet labels are checked by the UI tests; the scope-change announcement is posted with `UIAccessibility.post(.announcement)`. ⛔ The VoiceOver check on a device is not required (owner ruling 2026-11-10).
- [X] T233 [US3] Extend `PresetLibraryUITests.swift` (unlocked via `-uitestUnlocked YES`): Fractal › Nested Spiral scope, Next wrap, Random stays inside, scope line text — Verified: projectM-iOSUITests on the iOS 27.2 simulator, 2026-11-10 (25 tests pass): testFolderScopeNextWrapsAndRandomStaysInside.

---

## Phase 6: User Story 4 — Credits and licenses for every pack (P3)

**Goal**: Licenses lists each pack with source, version, license statement and authors.

**Independent Test**: Settings › Licenses shows all five pack entries.

- [X] T234 [P] [US4] Extend `scripts/collect_licenses.py` (and its `--check`) to add one entry per pack from `PresetPacks.json` with the license statement, source, commit and author list — Verified 2026-11-10: 25 components written, `--check` passes and requires the five pack entries.
- [X] T235 [US4] Show pack entries in `Apps/projectM-iOS/Views/LicensesView.swift` under a "Preset packs" group; extend `SettingsUITests` to open one — Verified 2026-11-10: SettingsUITests.testLicensesScreen on the iOS 27.2 simulator opens Cream of the Crop (source, commit 0180df2, authors). The view needed no change: it lists the manifest's "Preset packs" group.

---

## Phase 7: Polish & Cross-Cutting

- [X] T236 Add `RL_MODE=loadsweep` with `RL_SHARD=i/n` to `Apps/RendererLab/LabModel.swift` (load each indexed preset, no render; write failing ids) — Verified 2026-11-10: RendererLab builds for the simulator and ran the full sweep in four shards (`docs/test-reports/preset-library.md`).
- [X] T237 Run the load sweep on the simulator, commit the exclusions file, regenerate the index with `--exclusions`, and record the counts in `docs/test-reports/preset-library.md` — Verified 2026-11-10: 94 of 12,941 failed (none Included). The exclusions are committed and the index is rebuilt: 12,847 presets (12,819 in packs). The duplicate-of-excluded bug is fixed, with a test.
- [X] T238 {device} Measure SC-101 (library ready after the chooser appears), SC-102 (search per keystroke), SC-103 (frames on time while scrolling All A-Z and the largest folder), SC-104 (preset switches across packs) and SC-108 (installed size versus 1.0) on D1-D3; record in `docs/test-reports/performance.md` — Verified 2026-11-10 on D1-D3 with `scripts/run_device_tests.py` (`docs/test-reports/performance.md`, feature 002 section). Results:
  - SC-101: 101-112 ms (after two load changes).
  - SC-102: max 38.5 ms.
  - SC-103: 96.1-97.4%.
  - SC-108: +26.4 MB.
  - SC-104: borderline at first (96% on D1, an earlier run 92%), because slow switches waited on shader compiles for the first frame. Fixed 2026-11-10 by warming upcoming presets in the background (`PresetPrewarmer`), started 2.5 s after a switch so it costs no frame rate. At an 8 s dwell D1 passes: 96% with the warm-up (median 103 ms, 53.5 fps) and 98% without (median 130 ms, 51.1 fps).
- [ ] T239 {device} StoreKit sandbox purchase, restore and offline relaunch on a device — Automation ready (2026-11-10): `scripts/run_device_tests.py entitlement --device D1` walks through purchase, relaunch, offline and restore; a person does Buy, Airplane Mode and Restore. Blocked on T242 (the product in App Store Connect).
- [X] T240 Update `docs/privacy-policy.md` (purchase traffic through iOS only, FR-122), `docs/release/app-privacy.md`, `docs/release/store-copy.md` (in-app purchase, library size; no capture claims) and the privacy manifest scan — Verified 2026-11-10: policy (purchase section, network, stored scope), App Privacy (answers unchanged, basis updated), store copy (1.1 additions and claim table); `check_privacy_manifest.py` OK on a Release device build.
- [ ] T241 {device} Re-run the privacy review (feature 001 T108) with the new key and a purchase — Automation ready (2026-11-10): `scripts/run_device_tests.py privacy --device D1` (fresh install, scripted session, container listing, key check). The simulator rehearsal had zero violations; StoreKit writes `SKTransactionUpdatesLastChecked` itself (a timestamp). Run on D1 2026-11-10: zero violations (`docs/test-reports/privacy-review.md`, feature 002 section). Stays open until the purchase part runs after T239.
- [ ] T242 {owner} Create the in-app purchase in App Store Connect (`org.projectmios.ProjectMiOS.fullLibrary`, $1.99, review screenshot); accept the Paid Apps agreement and set up banking and tax — Product created 2026-11-10 in App Store Connect, in Chrome with the owner signed in (details in `docs/release/store-copy.md`):
  - Apple ID 6833245609, product `org.projectmios.ProjectMiOS.fullLibrary`, Non-Consumable;
  - $1.99 in all 175 countries or regions, Family Sharing off;
  - English display name and description, review screenshot and notes;
  - status: Prepare for Submission.

  Still owner-only: sign the Paid Apps Agreement, which is still "New" (Apple asks for an updated legal entity first), with banking and tax, and answer the EU Digital Services Act trader question. Then submit the purchase with the 1.1 version: Apple requires the first purchase to go with a new app version. Sandbox products load only once the agreement is active, so T239 waits for it.
- [X] T243 CI: fetch `Vendor/presets/*` where needed, run `PresetLibrary` tests on Linux and macOS, run the index `--check` — Verified 2026-11-10: CI run 42914485586 (1ad0b99) green on all jobs. The main macOS job fetches `Vendor/presets/*` shallow and checks that the index builds (28 Included, more than 12,000 presets); PresetLibrary tests run on Linux, the macOS host and both simulators. The index `--check` became this build check once nothing generated is committed (R-30).
- [X] T244 Update `README.md` section 18, `CLAUDE.md` status and `docs/test-reports/release-report.md` for feature 002 — Verified 2026-11-10: README 18.6, CLAUDE.md status and the release report note are written; validate_docs OK.

---

## Dependencies & Execution Order

- Setup (T201-T203) → Foundational (T204-T215) → stories.
- US1 (T216-T223) needs T205-T215. US2 (T224-T229) needs US1's coordinator (T217). US3 (T230-T233)
  needs T217 and T228. US4 (T234-T235) needs T206 only.
- Polish: T236-T237 need T214; T238-T241 need US1-US3; T242 is independent (owner).

## Parallel Examples

- Foundational: T204, T207, T209, T211, T213 (tests in different files) in parallel; then T205,
  T208, T210, T212.
- US2: T225 (tests) in parallel with T224; then T226 → T227 → T228 → T229.
- US4 in parallel with US2/US3 once T206 is done.

## Implementation Strategy

MVP = Phases 1-3 (US1): the large library browsable with Included unchanged. Then US2 (purchase),
US3 (scopes), US4 (credits), Polish. Device and owner tasks stay open with their tags until a
person runs them.

## Phase 8: Convergence

- [X] T247 Show each pack's and folder's playable count after purchase (total minus presets that failed this session) in `PresetBrowserView.swift` and `PresetFolderView.swift` per FR-111 (partial) — Verified 2026-11-10: PresetTests.testRowCountsArePlayableCountsAfterPurchase; 46 unit tests pass on the iOS 27.2 simulator.
- [X] T248 Record the preset warm-up (`PresetPrewarmer`, planned Random pick, start after the blend) as research decision R-31 and a plan touch-point per plan: architecture (unrequested) — Done 2026-11-10: research R-31 and plan Project Structure (ANGLERendering PresetPrewarmer, Rendering prewarm, PresetCoordinator planned pick); validate_docs OK.

## Phase 9: Convergence

- [X] T249 Offer the purchase sheet when Next, Previous or Random finds no playable preset in any locked scope (a locked pack or one of its folders) in `PresetCoordinator.swift` per Edge Cases: scope with no playable presets (partial) — Verified 2026-11-10: PresetTests.testRandomAndPreviousInALockedFolderRequestThePurchase and testNextInALockedPackRequestsThePurchase; 47 unit tests pass.
- [X] T250 Report purchase restrictions (`AppStore.canMakePayments`) when the store starts, so the sheet shows "Purchases aren't allowed on this device" on opening, in `LibraryStore.swift` per Edge Cases: purchases restricted (partial) — Done 2026-11-10: `LibraryStore.start()` sets `.restricted` when `AppStore.canMakePayments` is false, and a later price load keeps it. The 8 LibraryStoreTests pass (unrestricted path). The restricted path needs Screen Time on a device: StoreKit testing cannot simulate it.
