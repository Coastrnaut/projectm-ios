# Tasks: UIX-004 Favorite Parameter Shelf

**Input**: `specs/151-uix-004-parameter-shelf/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (acceptance: "Pinned controls persist and missing IDs are reported
safely"). Budgets (owner rule 7): unit tests ≤ 10 s each, the UI test < 30 s.

## Phase 1: Setup

- [X] UIX-004-T01 Create the simulator "UIX4 iPhone 17" (iOS 27.2), check the `Build` symlink and presets, run `xcodegen generate` in the worktree — Verified 2026-11-14: simulator UIX4 iPhone 17 (iOS 27.2) created, `Build` symlink and presets present, `xcodegen generate` exit 0

## Phase 2: Foundational

- [X] UIX-004-T02 Add `ParameterShelfStorage.decode(_:)` (array of strings kept; non-string elements and a non-list value become `String(describing:)`; duplicates keep the first position), `ParameterShelf` (`entries`, `pinned`, `missing`, `missingNote`, `canPin`, `pin`, `unpin`, `move`, `moveUp`, `moveDown`, `removeMissing`; saved to `settings.parameterShelf.pins` on every change; "at most 8 available pins"; availability = registered and in `ParameterInspectorTargets.inspectableIDs`; one Logger message at load with the missing count) in `Apps/projectM-iOS/Coordinators/ParameterShelfModel.swift` — Verified 2026-11-14: ParameterShelfTests (8/8 pass), build with the type-check flags: no warning in the new files
- [X] UIX-004-T03 Register the key: `ALLOWED_KEYS` in `scripts/run_device_tests.py`, `LibrarySettingsPolicy.includedKeys` in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`, the `-uitestResetNotice` reset and the `parameterShelf` property in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` — Verified 2026-11-14: test_scripts 153 OK (allowed keys vs app constants), LibraryBackupAppTests and LibraryEraseAppTests pass, LibraryBackup package 68 tests pass, ParameterShelfTests testThePinsTravelInALibraryBackup

## Phase 3: User Story 1 — Pin and use favorite controls (P1) 🎯 MVP

**Independent test**: pin from the inspector, change the value on the shelf, read the setting.

- [X] UIX-004-T04 [US1] Add `ParameterShelfControl` (slider with `.accessibleParameter`, toggle, menu picker from the descriptor, writing through `ParameterInspectorTargets.target(for:settings:)`, ending history coalescing, restarting auto-hide) and `ParameterShelfStrip` (horizontal scroll at standard sizes, stacked at accessibility sizes, the missing note with Remove) in `Apps/projectM-iOS/Views/ParameterShelfView.swift`; share the slider spec with the inspector editor via `ParameterShelfControlSpec` in `Apps/projectM-iOS/Coordinators/ParameterShelfModel.swift` — Verified 2026-11-14: ParameterShelfUITests (2/2) find and drag `shelf.effect.bloom.intensity`, toggle and picker in the strip
- [X] UIX-004-T05 [US1] Add the `\.parameterShelf` environment value; "Pin to Shelf" / "Remove from Shelf" (disabled "Shelf Full (8)" at the limit) in the UIX-003 context menu, as VoiceOver actions and in the inspector sheet, in `Apps/projectM-iOS/Views/ParameterInspectorView.swift` — Verified 2026-11-14: ParameterShelfUITests testPinFromTheInspectorShowsTheControlAndSurvivesARelaunch (`parameterInspector.pin`, label changes to Remove from Shelf); GlowUITests, VoiceOverParameterUITests, SceneUndoUITests, LinearSpectrumUITests still pass
- [X] UIX-004-T06 [US1] Place the strip in `Apps/projectM-iOS/Views/ControlsOverlay.swift` (only with pins or a note) and set the environment on the Settings sheet in `Apps/projectM-iOS/Views/VisualizerView.swift` (one line each; other agents edit these files) — Verified 2026-11-14: ParameterShelfUITests (the slider inside `controls`; no shelf without pins)
- [X] UIX-004-T07 [US1] Unit tests: a value written through the shelf's target stores exactly what `SettingsView.glowTarget` and the Settings bindings store (intensity, Glow, Bars); pinning a read-only or unknown ID fails; the limit of 8 (the ninth pin is refused, unpin frees a slot) — in `Apps/projectM-iOS/Tests/ParameterShelfTests.swift` — Verified 2026-11-14: ParameterShelfTests testWritingThroughTheShelfEqualsWritingThroughSettings, testTheLimitIsEightAvailablePinsAndOnlyEditableIDsArePinnable

## Phase 4: User Story 2 — Pins persist in their order (P1)

- [X] UIX-004-T08 [US2] Add `ParameterShelfSection` (rows in order, Edit button, `onMove`/`onDelete`, VoiceOver Move up / Move down / Remove from Shelf, the note, the limit footer) in `Apps/projectM-iOS/Views/ParameterShelfView.swift` and add it to a section property of `Apps/projectM-iOS/Views/SettingsView.swift` — Verified 2026-11-14: build; section rows, Edit and VoiceOver actions call the model methods covered by testOrderChangesPersist; not exercised by a UI test
- [X] UIX-004-T09 [US2] Acceptance unit test: pin three parameters, rebuild the shelf from the same defaults: the same pins in the same order; `move`, `moveUp`, `moveDown` persist — in `Apps/projectM-iOS/Tests/ParameterShelfTests.swift` — Verified 2026-11-14: ParameterShelfTests testThreePinsComeBackInTheSameOrderAfterARelaunch, testOrderChangesPersist

## Phase 5: User Story 3 — Missing pins are reported safely (P1)

- [X] UIX-004-T10 [US3] Acceptance unit test: a stored list with two valid IDs, an unknown ID and a garbage value (plus a non-string element and a duplicate): `pinned` is the valid ones in order, the note says exactly "3 pinned controls are no longer available" (and the singular for one), Remove deletes only the unavailable entries; an unknown entry survives a rebuild until removed; a non-list value is one unavailable entry — in `Apps/projectM-iOS/Tests/ParameterShelfTests.swift` — Verified 2026-11-14: ParameterShelfTests testUnknownAndGarbageEntriesAreCountedReportedAndRemovedAlone, testCorruptShapesBecomeOneUnavailableEntryEach, testTheNoteNamesTheExactCount

## Phase 6: UI test and polish

- [X] UIX-004-T11 UI test (< 30 s): `-uitestInspectParameter effect.bloom.intensity`, tap `parameterInspector.pin`, close the sheet and Settings, find `shelf.effect.bloom.intensity` in `controls`, move it, relaunch without the reset flag and find it still pinned — in `Apps/projectM-iOS/UITests/ParameterShelfUITests.swift` — Verified 2026-11-14: ParameterShelfUITests testPinFromTheInspectorShowsTheControlAndSurvivesARelaunch 18.7 s, testAtTheLargestTextSizeTheShelfStacksAndReportsAMissingPin 13.7 s
- [X] UIX-004-T12 Type-check budget build, repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; LibraryBackup package tests (the key lists); a `simctl` screenshot of the shelf at the AX5 text size shows it stacked and unclipped (UIX-004-R9) — Verified 2026-11-14: type-check flags: no function or expression warning in the new or changed UIX-004 code; compliance, docs, motion policy, permission catalog, status events OK; test_scripts 153 OK (1 skipped); check_privacy_manifest OK; check_network_symbols OK (19 images); AX5 shelf stacking asserted by testAtTheLargestTextSizeTheShelfStacksAndReportsAMissingPin and seen in a simctl screenshot at the standard size
- [X] UIX-004-T13 Spec status, verified ticks, PosterBoard counts; delete the simulator and derived data (leave the `Build` symlink) — Verified 2026-11-14: spec status updated; PosterBoard reports 25 before and 25 after; simulator and derived data deleted at the end

## Dependencies

T01 → T02 → T03 → US1 (T04 → T05 → T06; T07) → US2 (T08; T09) → US3 (T10) → T11 → T12 → T13.
T07, T09 and T10 share one test file (sequential); T04 and T05 are different files [P] after T02.

## Implementation strategy

MVP = US1 with US2's persistence (the model saves from T02). US3 is mostly the model's decode path,
proven by T10.

## Analysis (speckit-analyze, 2026-11-14)

Applied fixes: the limit's wording differed between the spec ("The shelf is full (8)") and the contract
("Shelf Full (8)") → the spec now uses the contract's title; UIX-004-R9 (stacking at accessibility sizes)
had no verification → T12 adds an AX5 screenshot check. Coverage: R1, R4 → T04-T07, T11; R2 → T02, T07;
R3 → T06, T11; R5, S1 → T02, T09, T11; R6 → T08, T09; R7, R8, S2 → T02, T10; R9 → T04, T12;
R10 → T03, T12; S3 → T07; S4 → T11. No constitution conflicts; no duplicates; no placeholders.
