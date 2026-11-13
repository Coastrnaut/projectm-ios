# Tasks: ACC-002 Reduced Flash Preset Policy

**Input**: `specs/030-acc-002-reduced-flash-preset-policy/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the row (accessibility unit/UI tests on the simulator). Tests are
deterministic (no wall clock, no sleeps); each unit test runs in about a second or less, each
package suite in under a minute, the UI test in under 30 s (owner rule 7). Logs go to
`.build/scratch/`. Device-only checks are tagged `{device}` and are not run by this row.

Format: `- [ ] ACC-002-Tnn [P?] [Story?] description`. A task is ticked only when verified, with
" — Verified 2026-11-13: <how>".

## Phase 1: Setup

- [X] ACC-002-T01 Record the baseline before any code change: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`, `swift test --package-path Packages/PresetLibrary`; note results here. — Verified 2026-11-13: check_compliance OK, validate_docs OK (293 files), test_scripts 99 tests OK (1 skipped) in 6.2 s, `swift test --package-path Packages/PresetLibrary` 194 tests, 0 failures, 27.2 s (logs .build/scratch/acc002-*-baseline.log).
- [X] ACC-002-T02 [P] Write the fixtures in `Packages/PresetLibrary/Tests/PresetLibraryTests/FlashFixtures/`, own text only (no third-party preset text): `high-flash.milk` (beat-driven `invert` plus `gamma` from `frame%2`: toggle-driven and luma-flicker), `calm.milk` (slow motion, the damped decay idiom), and one file per rule and exemption: `toggle-flip.milk`, `fast-sine.milk` (decay from `sin(time*30)`), `rand-gamma.milk`, `damped-idiom.milk`, `close-if.milk` (`decay = if(equal(frame%20,0),.99,1)`), `dead-toggle.milk` (driven `invert` then `invert = 0`), `slow-time-toggle.milk` (`darken = above(sin(time*0.5),0)`), `comment-only.milk` (`// invert = above(bass,1)`); plus `expected.json` mapping each file name to its rule ids. Add `resources: [.copy("Golden"), .copy("FlashFixtures")]` in `Packages/PresetLibrary/Package.swift`. — Verified 2026-11-13: 12 fixtures plus expected.json, all written for this repository (header comment says so); `.copy("FlashFixtures")` in Package.swift; `Bundle.module` finds them (PresetFlashRiskTests).

## Phase 2: Foundational — the classifier (blocks every story)

- [X] ACC-002-T03 [P] Python parity tests in `scripts/test_scripts.py`: every fixture's `classify` result equals `expected.json`; `high-flash.milk` flagged, `calm.milk` not (ACC-002-S1). — Verified 2026-11-13: `FlashRiskTests` in test_scripts.py: 4 tests pass (fixture parity over all 12 files, high-flash flagged / calm not, index field, stamp); full script suite 103 tests OK (1 skipped), 6.2 s.
- [X] ACC-002-T04 [P] Swift tests in `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetFlashRiskTests.swift`: every fixture equals `expected.json` (loaded with `Bundle.module`); high-flash flagged with `[.toggleDriven, .lumaFlicker]`; calm not; inline cases for statement splitting across `per_frame_N` lines, audio followed through a variable, `per_frame_init` ignored. — Verified 2026-11-13: `PresetFlashRiskTests` 7 tests pass on the macOS host, each ≤ 0.005 s; fixture parity, high-flash `[.toggleDriven, .lumaFlicker]`, inline cases, import screening.
- [X] ACC-002-T05 Implement `scripts/preset_flash_risk.py` per research ACC-002-D2 and contracts/flash-risk-classifier.md (rules `toggle-driven`, `toggle-flip`, `luma-flicker`; thresholds N ≤ 20, K ≥ 18, frame K ≥ 0.3, damping 0.1; dead constant assignments). — Verified 2026-11-13: `scripts/preset_flash_risk.py`; T03 passes. Survey over the pinned packs in research ACC-002-D2/D3.
- [X] ACC-002-T06 Implement `Packages/PresetLibrary/Sources/PresetLibrary/PresetFlashRisk.swift` as a line-for-line port (Foundation `NSRegularExpression`, Linux-safe, explicit closure types); T03 and T04 pass. — Verified 2026-11-13: `PresetFlashRisk.swift`; T04 passes; corpus parity: a scratch release build of the Swift twin and the Python module give identical rules for all 14,576 pack `.milk` files (0 differences, 92 flagged by each), rechecked after the Linux-safety change (NSString(string:), String(decoding:as:)). Linux itself not run on this host (CI covers it).

## Phase 3: User Story 4 — every preset is screened (P2, but blocks US1-US3's data)

**Goal**: the flag reaches the library for bundled and imported presets. **Independent test**: an index record with `flash` decodes to `mayFlash == true`; one without decodes to false; an imported high-flash fixture gets a flag.

- [X] ACC-002-T07 [US4] `scripts/build_preset_index.py`: call `preset_flash_risk.classify` for every record (Included files and pack payloads, UTF-8 with replacement) and add `"flash": [...]` only when non-empty; add `preset_flash_risk.py` to the stamp; tests in `scripts/test_scripts.py` that a built index over a temporary packs folder holding the high-flash fixture carries `flash` and the calm one does not. — Verified 2026-11-13: test_scripts `test_index_carries_flash_only_for_flagged_records` and `test_stamp_covers_the_classifier` pass; real index built (T17).
- [X] ACC-002-T08 [P] [US4] `specs/002-preset-library-unlock/contracts/preset-index.schema.json`: optional `flash` (array of the three rule ids, `minItems` 1, unique); a script test validates a built index's records against the schema's allowed keys. — Verified 2026-11-13: schema has optional `flash` (enum of the three ids, minItems 1, uniqueItems); the script test checks every built record's keys against the schema.
- [X] ACC-002-T09 [US4] `IndexedPreset.flash: [String]?` (initializer parameter defaulted to nil) and `mayFlash` in `PresetIndex.swift`; tests in `PresetLibraryTests.swift`: an index with and without `flash` decodes ("absent = not flagged", ACC-002-R13), version stays 1. — Verified 2026-11-13: `PresetLibraryTests.testFlashFieldIsOptionalAndAdditive` passes; package suite 201 tests, 0 failures, 25.3 s.
- [X] ACC-002-T10 [US4] `UserPresetLibrary.flashRisk()` (playable ids → rule ids, flagged only, cached per sha256) and `UserPreset.indexed(flash:)`; `UserPresetsCoordinator.refresh` passes the flags into `setUserPresets`; package test: a stored high-flash user preset is reported, a calm one is not. — Verified 2026-11-13: `PresetFlashRiskTests.testImportedPresetsAreScreened` passes (high-flash fixture imported and flagged, calm not, cache stable); UserPresetsCoordinator passes the flags; UI test T15 shows the imported fixture flagged in My Presets.

## Phase 4: User Story 1 — skipped automatically (P1) 🎯 MVP

**Goal**: with Reduce flashing on, Next, Previous, Random, warm-up and the launch preset never pick a flagged preset. **Independent test**: `FlashPolicyTests` with a fake library of calm/flagged/calm.

- [X] ACC-002-T11 [US1] Tests in `Apps/projectM-iOS/Tests/FlashPolicyTests.swift`: policy on, Next from calm A lands on calm C (skipping flagged B), Previous likewise; 200 Random picks never B and the warm-up list never holds B; policy off, Next lands on B (unchanged); every member flagged → nothing loads and `failureMessage == "Every preset here may flash."`; the launch preset skips a flagged last preset; a flagged preset already on screen keeps playing when the setting turns on (Edge Cases). — Verified 2026-11-13: `FlashPolicyTests` (10 tests) pass on the iOS 27.2 simulator iPhone 17 (4E32B01D), each ≤ 0.026 s.
- [X] ACC-002-T12 [US1] `PresetCoordinator`: `isFlagged`, `walkable`, the walk in `step`, `random`, `planUpcoming` and `initialPreset`, the all-flagged message (contracts/flash-policy.md); T11 passes. — Verified 2026-11-13: T11 passes; `walkable` drives step, random, planUpcoming and initialPreset.

## Phase 5: User Story 2 — warned before load (P1)

**Goal**: an explicit flagged choice shows a warning and nothing loads until Load Anyway. **Independent test**: unit tests on the coordinator and the UI test with the imported fixture.

- [X] ACC-002-T13 [US2] Tests in `FlashPolicyTests.swift`: policy on, `choose(B)` sets `flashWarning` and the loader saw nothing; `cancelFlashWarning()` loads nothing; `confirmFlashWarning()` loads B and sets its scope; policy off, `choose(B)` loads at once; a locked flagged preset asks for the purchase first, and after the unlock it is warned instead of loaded; no UserDefaults key is written by a warning, Cancel or Load Anyway (ACC-002-R12). — Verified 2026-11-13: the US2 tests in `FlashPolicyTests` pass (warning, Cancel, Load Anyway, scope, off-path, locked then warned, written keys exactly settings.reduceFlashing, lastPresetID, settings.presetScope).
- [X] ACC-002-T14 [US2] `PresetCoordinator.flashWarning`, `confirmFlashWarning()`, `cancelFlashWarning()`, the purchase path through `choose`; `AppCoordinator.choose` keeps the browser open while a warning is pending; the alert on `PresetBrowserView`'s stack ("May flash", Load Anyway / Cancel, identifiers `loadFlaggedAnyway`, `cancelFlagged`; a standard alert, so VoiceOver announces it and its text follows Dynamic Type, ACC-002-R14); closing the browser while warned cancels the warning; T13 passes. — Verified 2026-11-13: T13 passes; alert on the browser stack and on the visualizer; T15 drives Cancel and Load Anyway in the app.
- [X] ACC-002-T15 [US2] UI test `Apps/projectM-iOS/UITests/FlashPolicyUITests.swift`: launch with `-settings.reduceFlashing YES`, `-uitestUnlocked NO`, import `high-flash.milk` through `-uitestImportPreset`, open My Presets, check the row's "May flash" mark and label, choose it → the alert appears and `currentPreset` is unchanged; Cancel → unchanged; choose again → Load Anyway → `currentPreset` becomes the fixture; under 30 s (ACC-002-S2). — Verified 2026-11-13: `FlashPolicyUITests.testTheHighFlashFixtureIsFlaggedBeforeItLoads` passed twice on iPhone 17 (4E32B01D), 15.7 s and 15.0 s: row label "Strobe, by Fixture, may flash", alert shown while the previous preset stays current, Cancel keeps it, Load Anyway loads "Strobe".

## Phase 6: User Story 3 — the browser marks flagged presets (P2)

- [X] ACC-002-T16 [US3] `PresetRow` in `PresetBrowserView.swift`: policy on and flagged → `exclamationmark.triangle` + "May flash" (caption, secondary, not color-only; identifier `mayFlash:<name>`), and ", may flash" in the row's accessibility label; policy off → unchanged. Unit test of the label text helper in `FlashPolicyTests.swift`; the row is checked by T15. — Verified 2026-11-13: `testRowLabelsSayMayFlashOnlyWhileReduceFlashingIsOn` passes; the UI test reads the row label.

## Phase 7: Polish & cross-cutting

- [X] ACC-002-T17 Corpus count (information): build the index from the main checkout's pinned submodules into `.build/scratch/acc002-index` (quickstart §2); record flagged/total here and in research ACC-002-D3, and the index step's time with and without the classifier (ACC-002-S4). — Verified 2026-11-13: index built from the main checkout's pinned submodules into .build/scratch/acc002-index: **83 of 12,847 presets flagged** (cream-of-the-crop 63, projectm-classic 19, milkdrop-original 1; Included 0; toggle-driven 73, luma-flicker 10, toggle-flip 0). Index step 8.1 s with the classifier, 2.9 s without (+5.2 s; S4 < 30 s).
- [X] ACC-002-T18 Gates: `check_compliance.py`, `validate_docs.py`, `test_scripts.py`, `swift test --package-path Packages/PresetLibrary` (with durations); `git diff autonomous/integration --stat` shows no change under `Packages/FlashSafety`, `Packages/ANGLERendering` or `Packages/Rendering` (ACC-002-R11: the runtime limit is untouched). — Verified 2026-11-13: check_compliance OK; validate_docs OK (293 files); test_scripts 103 OK (1 skipped) 6.2 s; PresetLibrary 201 tests, 0 failures, 25.3 s; `git diff $(git merge-base HEAD autonomous/integration) --stat -- Packages/FlashSafety Packages/ANGLERendering Packages/Rendering` is empty (R11).
- [X] ACC-002-T19 App on the simulator (quickstart §3): `xcodegen generate`, `projectM-iOSTests` and `FlashPolicyUITests` on iPhone 17 (4E32B01D); count new PosterBoard reports. — Verified 2026-11-13: `xcodegen generate`, build-for-testing (TEST BUILD SUCCEEDED, no warnings in touched files); `projectM-iOSTests` 156 tests with 1 failure, the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (worktree has no preset submodules: 28 presets indexed); `FlashPolicyUITests` 1/1, 15.0 s; whole run 32.7 s. PosterBoard reports: 32 before and after (none new).
- [ ] ACC-002-T20 {device} On D1 with Reduce flashing on: VoiceOver reads "may flash" on flagged rows and the alert; Random 50 times without a flagged preset; the alert at the largest text size (quickstart §4).

## Dependencies

T01 → T02 → (T03, T04) → (T05, T06) → T07-T10 (US4) → T11-T12 (US1) → T13-T15 (US2) → T16 (US3) → T17-T19 → T20 `{device}`. US1, US2 and US3 all read `IndexedPreset.mayFlash` (T09). T15 also covers T16's row.

## Parallel opportunities

T03 ∥ T04 (Python and Swift tests); T05 ∥ T06; T08 ∥ T09.

## Implementation strategy

MVP: Phases 1-4 (classifier, index flag, automatic skip). Then the warning (the row's acceptance
criterion), then the mark. Device validation is the last stage and belongs to the integrator.
