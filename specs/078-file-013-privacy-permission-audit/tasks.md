# Tasks: FILE-013 Privacy Permission Audit

**Input**: `specs/078-file-013-privacy-permission-audit/` (spec, plan, quickstart)

Budgets (owner rule 7): unit tests about 1-2 s, UI tests < 30 s each. Simulator results are never
device evidence. Shared files (SCN-012 and ACC-001 run in parallel) get small edits only.

## Phase 1: Foundational — the catalog (blocks every story)

- [ ] FILE-013-T01 `Apps/projectM-iOS/Coordinators/PermissionCatalog.swift`: `AppPermission`,
  `PermissionState`, `PermissionEntry`, `PermissionNotice`, `PermissionCatalog` (entries with key,
  usage text identical to `project.yml`, policy name, features, asked-when, settings flag, distinct
  restricted flag; `notice(_:_:)`; the plan D5 mappings; Photos note; `openSettings()`) (FILE-013-R1, R2)
- [ ] FILE-013-T02 `Apps/projectM-iOS/Tests/PermissionCatalogTests.swift`: every mapping from injected
  statuses; denied and restricted notice text and Open Settings for all 4 permissions; catalog usage
  texts equal the built `Bundle.main.infoDictionary`; no Photos library key in the bundle
  (FILE-013-R5, S1)

## Phase 2: US1 + US2 — denied and restricted behaviour (P1)

**Independent test**: deny or restrict each permission (real where possible, injected otherwise) and
read the notice.

- [ ] FILE-013-T03 [US1] `Apps/projectM-iOS/Views/PermissionNoticeView.swift` (plan D6); camera notice in
  `VisualizerView.swift` uses it with the catalog's notice (identifiers unchanged) (FILE-013-R3)
- [ ] FILE-013-T04 [US1] One opener: `AppCoordinator.handle(.openSettings)` and both notices call
  `PermissionCatalog.openSettings()` (FILE-013-R4)
- [ ] FILE-013-T05 [US1] Local Network: `OSCReceiverCoordinator.statusText` reads the catalog's text;
  `SettingsView.swift` OSC section shows `PermissionNoticeView` (`localNetwork…`, Open Settings) while
  denied (FILE-013-R3, R4)
- [ ] FILE-013-T06 [US1] [US2] DEBUG stand-ins: `Apps/projectM-iOS/Debug/UITestOSCFailure.swift`
  (`-uitestOSCFailure localNetworkDenied`) wired in `AppCoordinator.swift`;
  `-uitestFakeAvailability <reason>` in `UITestFakeSource.swift` (FILE-013-R8)
- [ ] FILE-013-T07 [US1] [US2] `Apps/projectM-iOS/UITests/PermissionAuditUITests.swift`: real microphone
  denial (gated on `FILE013_MIC_REVOKED`, Open Settings brings iOS Settings forward); camera
  restricted with Open Settings → iOS Settings; Local Network denied notice; screen capture restricted
  row (FILE-013-R7, R8, S3, S5)
- [ ] FILE-013-T08 [US1] [US2] Run on an own iOS 27.2 simulator: unit tests, `PermissionAuditUITests`
  with the microphone revoked, `CameraUITests`, `OSCReceiverUITests`, `GuidedFirstSceneUITests`,
  `StatusUITests/testStartFailureMessagesAndActions`; PosterBoard count before and after
  (FILE-013-R11, S1, S5)

## Phase 3: US3 — one place, checked (P2)

- [ ] FILE-013-T09 [US3] `scripts/check_permission_catalog.py` (plan D10) and
  `PermissionCatalogCheckTests` in `scripts/test_scripts.py`: repository OK; missing entry, extra key,
  changed text, Photos key, policy mismatch each fail (FILE-013-R6, S2, S4)
- [ ] FILE-013-T10 [US3] `docs/privacy-policy.md` "Permissions and why" matches the catalog exactly
  (names, timing, denied/restricted behaviour, Photos needs none); CI docs job runs the check
  (`.github/workflows/ios-ci.yml`) (FILE-013-R10)
- [ ] FILE-013-T11 {device} D1: deny Microphone, Camera and Local Network in Settings and use each
  feature; restrict Camera with Screen Time and use the Camera visual; notices match the catalog
  (FILE-013-R9)

## Phase 4: Polish

- [ ] FILE-013-T12 Gates: `check_compliance.py`, `validate_docs.py`, `test_scripts.py`,
  `check_permission_catalog.py`, `check_privacy_manifest.py` on the Debug simulator app; spec status
  and audit "after" column (FILE-013-R11)

## Dependencies

T01 → T02-T06. T03-T06 → T07 → T08. T01 → T09 → T10. Everything → T12. T11 needs D1 and the owner.
Parallel: T02 with T03-T06 (different files); T09 with T03-T08.
