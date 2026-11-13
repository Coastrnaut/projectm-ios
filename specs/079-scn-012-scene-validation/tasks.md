# Tasks: SCN-012 Scene Validation

**Input**: Design documents from `specs/079-scn-012-scene-validation/` (spec, plan, research,
data-model, contracts/scene-repair-report.md, quickstart)

**Tests**: requested by the spec (SCN-012-S1 to S5) and the roadmap row ("schema round trip +
integration + simulator"). Budgets (owner rule 7): unit ≤ 10 s, suite < 1 min, UI test < 30 s,
property test ≤ 1 s.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [ ] SCN-012-T01 Confirm the worktree builds: `git submodule update --init --depth 1 Vendor/presets/*`, `xcodegen generate`, own simulator "SCN12 iPhone 17" (iOS 27.2); count PosterBoard reports before

## Phase 2: Foundational (the report model, blocks every story)

- [ ] SCN-012-T02 Implement `SceneRepairReport` (`Group`, `Severity`, `Entry`, `init(refusal:)`, `init(document:decodeWarnings:registry:assets:)`, `open(bytes:registry:assets:)`, `canOpenAsIs`, `canOpenWithRepairs`, `cannotOpen`, `needsReview`, `repairActions`, `groups`) and `SceneRepairAction` (nine actions, canonical order, titles, owned codes per data-model table) in Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift, Foundation-free (contract R1); add the file to Packages/SceneFormat/Tests/SceneFormatTests/SceneSourceSafetyTests.swift
- [ ] SCN-012-T03 Implement `SceneDocument.repairing(_:registry:assets:)` in Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift: canonical order, each action re-validates; renumber per research D3 ("smallest positive ID not yet used"); mappings per research D4; never touches the scene ID, unknown layers, unknown fields or unknown parameter values (contract R2)

## Phase 3: User Story 1 + 2 + 3 — the report and repairs (P1, P2), pure

**Goal**: every malformed fixture gives the expected report; repairs open the repairable ones.
**Independent test**: SceneRepairTests on the host and the Linux shape.

- [ ] SCN-012-T04 [P] [US1] [US2] [US3] Fixture table in Packages/SceneFormat/Tests/SceneFormatTests/SceneRepairTests.swift: truncated JSON, oversize, duplicate key, newer version, invalid version → one cannotOpen entry in damagedFile/unsupportedVersion with no actions; duplicate instance IDs, missing photo, dangling asset, dangling binding target, modulation cycle, unknown layer kind, unknown material, invalid name, clamped values → exact (group, severity, code, actions) lists and flags (S1)
- [ ] SCN-012-T05 [P] [US3] Repair tests in the same file: each repairable fixture repaired with `report.repairActions` validates with no errors; repairing twice equals once; action order given does not matter; unknown layer kind and the scene ID kept; the missing-photo repair removes the photo layer and asset only (S2)
- [ ] SCN-012-T06 [P] [US1] Seeded fuzz (500 cases, ≤ 1 s) in the same file: byte mutations and document mutations; a report for each, repaired documents encode and decode, repairs idempotent (S3)

## Phase 4: User Story 1 + 2 — show cues in the app (P1)

**Goal**: stepping to a cue with problems shows the report before applying.
**Independent test**: SceneRepairCoordinatorTests, ShowCoordinatorTests; SceneRepairUITests.

- [ ] SCN-012-T07 [US1] `SceneRepairRequest` and `SceneRepairCoordinator` (present replaces and cancels a pending request; openWithRepairs, openAsIs only when `canOpenAsIs`, cancel) in Apps/projectM-iOS/Coordinators/SceneRepairCoordinator.swift; `SceneRepairReportView` (grouped list, status text, buttons, identifiers per contract R4, VoiceOver headings) in Apps/projectM-iOS/Views/SceneRepairReportView.swift; present from Apps/projectM-iOS/Views/VisualizerView.swift and over Settings (Apps/projectM-iOS/Views/SettingsView.swift host) so the show editor's Go to Cue gets it (research D5)
- [ ] SCN-012-T08 [US1] [US2] Route show steps in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift (refusal → request; `needsReview` → request; output unchanged until Open; stored file never written) and wire in Apps/projectM-iOS/Coordinators/AppCoordinator.swift / AppCoordinator+Show.swift (contract R3; the apply path itself is unchanged, so a blackout stays black)
- [ ] SCN-012-T09 [US1] [US2] App tests in Apps/projectM-iOS/Tests/SceneRepairCoordinatorTests.swift and updated Apps/projectM-iOS/Tests/ShowCoordinatorTests.swift: a broken cue requests review and applies nothing; open with repairs applies the repaired scene and leaves the file bytes unchanged; open as is refused with errors; cancel applies nothing; newer-version cue → cannotOpen request; clean cues apply as before (S5)
- [ ] SCN-012-T10 [US1] [US2] DEBUG `-uitestShowRepairSeed` in Apps/projectM-iOS/Debug/UITestShowFixture.swift (cue 1 good, cue 2 missing photo + dangling binding, cue 3 newer version) and Apps/projectM-iOS/UITests/SceneRepairUITests.swift: Next → report with Missing media and Invalid mappings (group headers are header elements, R13) → Open with repairs → cue 2 applied as circular spectrum; Next → "Cannot open" → Cancel, output unchanged; under 30 s (S4)

## Phase 5: User Story 4 — other openers (P2)

- [ ] SCN-012-T11 [US4] PERF-010 Reopen route in Apps/projectM-iOS/Coordinators/AppCoordinator.swift (held scene report `needsReview` → request before `markReopened`; Cancel keeps the offer) and `repairReport` on `SceneArchiveImportResult` in Apps/projectM-iOS/Coordinators/SceneArchiveService.swift; tests in Apps/projectM-iOS/Tests/SceneRepairCoordinatorTests.swift (reopen decision) and an assertion in Apps/projectM-iOS/Tests/SceneArchiveServiceTests.swift; launch restore unchanged

## Phase 6: Polish

- [ ] SCN-012-T12 Amend docs/adr/0028-scene-document-format.md (repair report, actions, decisions D1-D6); spec status; `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`; run quickstart steps 1-2 (projectM-iOSTests, SceneRepairUITests, ShowCueUITests, SessionRecoveryUITests); PosterBoard count after; delete the own simulator

## Dependencies

T01 → T02 → T03 → (T04, T05, T06 in parallel) → T07 → T08 → T09, T10 → T11 → T12.

## Parallel example

T04, T05 and T06 are one new test file written in one pass; the app tasks share AppCoordinator and run
in order.

## Implementation strategy

MVP: T02-T06 (the pure report, Linux) then T07-T10 (show cues, the acceptance). T11 extends the same
coordinator to Reopen and the archive result.
