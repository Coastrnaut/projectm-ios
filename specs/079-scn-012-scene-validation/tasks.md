# Tasks: SCN-012 Scene Validation

**Input**: Design documents from `specs/079-scn-012-scene-validation/` (spec, plan, research,
data-model, contracts/scene-repair-report.md, quickstart)

**Tests**: requested by the spec (SCN-012-S1 to S5) and the roadmap row ("schema round trip +
integration + simulator"). Budgets (owner rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s,
property test ≤ 1 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [X] SCN-012-T01 Confirm the worktree builds: `git submodule update --init --depth 1 Vendor/presets/*`, `xcodegen generate`, own simulator "SCN12 iPhone 17" (iOS 27.2); count PosterBoard reports before — Verified 2026-11-13: preset submodules initialized, `xcodegen generate` OK, own simulator SCN12 iPhone 17 (iOS 27.2, 7B73A80A) created; PosterBoard reports 32 before

## Phase 2: Foundational (the report model, blocks every story)

- [X] SCN-012-T02 Implement `SceneRepairReport` (`Group`, `Severity`, `Entry`, `init(refusal:)`, `init(document:decodeWarnings:registry:assets:)`, `open(bytes:registry:assets:)`, `canOpenAsIs`, `canOpenWithRepairs`, `cannotOpen`, `needsReview`, `repairActions`, `groups`) and `SceneRepairAction` (nine actions, canonical order, titles, owned codes per data-model table) in Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift, Foundation-free (contract R1); add the file to Packages/SceneFormat/Tests/SceneFormatTests/SceneSourceSafetyTests.swift — Verified 2026-11-13: `swift test --package-path Packages/SceneFormat` 67/67 on the host (3.2 s) and in the Linux shape (2.7 s); SceneSourceSafetyTests list SceneRepair.swift and pass (no Foundation)
- [X] SCN-012-T03 Implement `SceneDocument.repairing(_:registry:assets:)` in Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift: canonical order, each action re-validates; renumber per research D3 ("smallest positive ID not yet used"); mappings per research D4; never touches the scene ID, unknown layers, unknown fields or unknown parameter values (contract R2) — Verified 2026-11-13: SceneRepairTests repair cases (testEachRepairTouchesOnlyItsItems, testOtherRepairsMakeErrorsOpenable, idempotency) pass on the host and the Linux shape

## Phase 3: User Story 1 + 2 + 3 — the report and repairs (P1, P2), pure

**Goal**: every malformed fixture gives the expected report; repairs open the repairable ones.
**Independent test**: SceneRepairTests on the host and the Linux shape.

- [X] SCN-012-T04 [P] [US1] [US2] [US3] Fixture table in Packages/SceneFormat/Tests/SceneFormatTests/SceneRepairTests.swift: truncated JSON, oversize, duplicate key, newer version, invalid version → one cannotOpen entry in damagedFile/unsupportedVersion with no actions; duplicate instance IDs, missing photo, dangling asset, dangling binding target, modulation cycle, unknown layer kind, unknown material, invalid name, clamped values → exact (group, severity, code, actions) lists and flags (S1) — Verified 2026-11-13: testRefusalsProduceACannotOpenEntryWithoutActions, testEachFixtureHasItsExactReport, testEntriesNameTheItemAndWhatHappensIfOpened, testAnInvalidSceneIDCannotOpenAndHasNoRepair pass (≤ 0.004 s each)
- [X] SCN-012-T05 [P] [US3] Repair tests in the same file: each repairable fixture repaired with `report.repairActions` validates with no errors; repairing twice equals once; action order given does not matter; unknown layer kind and the scene ID kept; the missing-photo repair removes the photo layer and asset only (S2) — Verified 2026-11-13: testRepairedFixturesValidateCleanlyAndRepairsAreIdempotent (0.005 s), testEachRepairTouchesOnlyItsItems, testOtherRepairsMakeErrorsOpenable pass
- [X] SCN-012-T06 [P] [US1] Seeded fuzz (500 cases, ≤ 1 s) in the same file: byte mutations and document mutations; a report for each, repaired documents encode and decode, repairs idempotent (S3) — Verified 2026-11-13: testSeededMutationsAlwaysReportAndRepairsDecodeAgain, 500 cases (125 through mutated bytes), 0.76-0.88 s on the host and the Linux shape

## Phase 4: User Story 1 + 2 — show cues in the app (P1)

**Goal**: stepping to a cue with problems shows the report before applying.
**Independent test**: SceneRepairCoordinatorTests, ShowCoordinatorTests; SceneRepairUITests.

- [X] SCN-012-T07 [US1] `SceneRepairRequest` and `SceneRepairCoordinator` (present replaces and cancels a pending request; openWithRepairs, openAsIs only when `canOpenAsIs`, cancel) in Apps/projectM-iOS/Coordinators/SceneRepairCoordinator.swift; `SceneRepairReportView` (grouped list, status text, buttons, identifiers per contract R4, VoiceOver headings) in Apps/projectM-iOS/Views/SceneRepairReportView.swift; present from Apps/projectM-iOS/Views/VisualizerView.swift and over Settings (Apps/projectM-iOS/Views/SettingsView.swift host) so the show editor's Go to Cue gets it (research D5) — Verified 2026-11-13: SceneRepairCoordinatorTests 6/6 (≤ 0.007 s each); SceneRepairUITests shows the sheet with its identifiers and buttons
- [X] SCN-012-T08 [US1] [US2] Route show steps in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift (refusal → request; `needsReview` → request; output unchanged until Open; stored file never written) and wire in Apps/projectM-iOS/Coordinators/AppCoordinator.swift / AppCoordinator+Show.swift (contract R3; the apply path itself is unchanged, so a blackout stays black) — Verified 2026-11-13: SceneRepairCoordinatorTests (broken cue requests review, applies nothing, file bytes unchanged after Open with repairs); ShowCoordinatorTests unchanged and passing; ShowCueUITests 2/2
- [X] SCN-012-T09 [US1] [US2] App tests in Apps/projectM-iOS/Tests/SceneRepairCoordinatorTests.swift and updated Apps/projectM-iOS/Tests/ShowCoordinatorTests.swift: a broken cue requests review and applies nothing; open with repairs applies the repaired scene and leaves the file bytes unchanged; open as is refused with errors; cancel applies nothing; newer-version cue → cannotOpen request; clean cues apply as before (S5) — Verified 2026-11-13: projectM-iOSTests 352/352 (19.0 s) on the own iOS 27.2 simulator
- [X] SCN-012-T10 [US1] [US2] DEBUG `-uitestShowRepairSeed` in Apps/projectM-iOS/Debug/UITestShowFixture.swift (cue 1 good, cue 2 missing photo + dangling binding, cue 3 newer version) and Apps/projectM-iOS/UITests/SceneRepairUITests.swift: Next → report with Missing media and Invalid mappings (group headers are header elements, R13) → Open with repairs → cue 2 applied as circular spectrum; Next → "Cannot open" → Cancel, output unchanged; under 30 s (S4) — Verified 2026-11-13: SceneRepairUITests 1/1 (12.1 s, then 9.9 s); the header trait is set in code but XCUITest cannot read traits, so only the group identifiers are asserted

## Phase 5: User Story 4 — other openers (P2)

- [X] SCN-012-T11 [US4] PERF-010 Reopen route in Apps/projectM-iOS/Coordinators/AppCoordinator.swift (held scene report `needsReview` → request before `markReopened`; Cancel keeps the offer) and `repairReport` on `SceneArchiveImportResult` in Apps/projectM-iOS/Coordinators/SceneArchiveService.swift; tests in Apps/projectM-iOS/Tests/SceneRepairCoordinatorTests.swift (reopen decision) and an assertion in Apps/projectM-iOS/Tests/SceneArchiveServiceTests.swift; launch restore unchanged — Verified 2026-11-13: testReopenShowsTheReportOnlyWhenTheHeldSceneNeedsReview; SceneArchiveServiceTests round trip asserts `repairReport` (5/5); SessionRecoveryUITests 3/3; launch restore code untouched

## Phase 6: Polish

- [X] SCN-012-T12 Amend docs/adr/0028-scene-document-format.md (repair report, actions, decisions D1-D6); spec status; `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`; run quickstart steps 1-2 (projectM-iOSTests, SceneRepairUITests, ShowCueUITests, SessionRecoveryUITests); PosterBoard count after; delete the own simulator — Verified 2026-11-13: ADR-0028 amended; `check_compliance.py` and `validate_docs.py` OK; PosterBoard reports 32 before and after; own simulator deleted

## Dependencies

T01 → T02 → T03 → (T04, T05, T06 in parallel) → T07 → T08 → T09, T10 → T11 → T12.

## Parallel example

T04, T05 and T06 are one new test file written in one pass; the app tasks share AppCoordinator and run
in order.

## Implementation strategy

MVP: T02-T06 (the pure report, Linux) then T07-T10 (show cues, the acceptance). T11 extends the same
coordinator to Reopen and the archive result.
