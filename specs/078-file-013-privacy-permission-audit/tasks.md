# Tasks: FILE-013 Privacy Permission Audit

**Input**: `specs/078-file-013-privacy-permission-audit/` (spec, plan, quickstart)

Budgets (owner rule 7): unit tests about 1-2 s, UI tests < 30 s each. Simulator results are never
device evidence. Shared files (SCN-012 and ACC-001 run in parallel) get small edits only.

## Phase 1: Foundational — the catalog (blocks every story)

- [X] FILE-013-T01 `Apps/projectM-iOS/Coordinators/PermissionCatalog.swift`: `AppPermission`,
  `PermissionState`, `PermissionEntry`, `PermissionNotice`, `PermissionCatalog` (entries with key,
  usage text identical to `project.yml`, policy name, features, asked-when, settings flag, distinct
  restricted flag; `notice(_:_:)`; the plan D5 mappings; Photos note; `openSettings()`) (FILE-013-R1, R2) — Verified 2026-11-13: `PermissionCatalogTests` (11 tests) pass in the app unit suite (357 tests, 0 failures, 14.4 s) on the FILE13 iPhone 17 (iOS 27.2) simulator; its built-Info.plist test found the missing camera key (audit finding 5), fixed in `project.yml`
- [X] FILE-013-T02 `Apps/projectM-iOS/Tests/PermissionCatalogTests.swift`: every mapping from injected
  statuses; denied and restricted notice text and Open Settings for all 4 permissions; catalog usage
  texts equal the built `Bundle.main.infoDictionary`; no Photos library key in the bundle
  (FILE-013-R5, S1) — Verified 2026-11-13: same run: all 11 pass (each ≤ 0.02 s except the Info.plist key scan, 1.1 s): 8 denied/restricted notices, 5 mappings, texts equal UIStrings/CameraFeedState/OSC status, built Info.plist has exactly the catalog's 4 keys and no Photos key

## Phase 2: US1 + US2 — denied and restricted behaviour (P1)

**Independent test**: deny or restrict each permission (real where possible, injected otherwise) and
read the notice.

- [X] FILE-013-T03 [US1] `Apps/projectM-iOS/Views/PermissionNoticeView.swift` (plan D6); camera notice in
  `VisualizerView.swift` uses it with the catalog's notice (identifiers unchanged) (FILE-013-R3) — Verified 2026-11-13: `CameraUITests` 2/2 pass with the shared view (identifiers unchanged; denied 10.6 s, granted 12.8 s); `testCameraRestrictedShowsNoticeAndOpensSettings` passes (17.3 s)
- [X] FILE-013-T04 [US1] One opener: `AppCoordinator.handle(.openSettings)` and both notices call
  `PermissionCatalog.openSettings()` (FILE-013-R4) — Verified 2026-11-13: `AppCoordinator.handle(.openSettings)` and both notices call `PermissionCatalog.openSettings()` (diff); the real microphone banner's and the camera notice's Open Settings each brought `com.apple.Preferences` to the foreground in PermissionAuditUITests
- [X] FILE-013-T05 [US1] Local Network: `OSCReceiverCoordinator.statusText` reads the catalog's text;
  `SettingsView.swift` OSC section shows `PermissionNoticeView` (`localNetwork…`, Open Settings) while
  denied (FILE-013-R3, R4) — Verified 2026-11-13: `testLocalNetworkDeniedShowsNoticeWithOpenSettings` passes (14.2 s): catalog text, `localNetworkOpenSettings`, status back on Off; `OSCReceiverUITests` (21.0 s) and `OSCNetworkAccessUITests` (17.0 s) still pass
- [X] FILE-013-T06 [US1] [US2] DEBUG stand-ins: `Apps/projectM-iOS/Debug/UITestOSCFailure.swift`
  (`-uitestOSCFailure localNetworkDenied`) wired in `AppCoordinator.swift`;
  `-uitestFakeAvailability <reason>` in `UITestFakeSource.swift` (FILE-013-R8) — Verified 2026-11-13: the two stand-ins drive the Local Network and screen-capture restricted UI tests above; DEBUG only (`#if DEBUG`)
- [X] FILE-013-T07 [US1] [US2] `Apps/projectM-iOS/UITests/PermissionAuditUITests.swift`: real microphone
  denial (gated on `FILE013_MIC_REVOKED`, Open Settings brings iOS Settings forward); camera
  restricted with Open Settings → iOS Settings; Local Network denied notice; screen capture restricted
  row (FILE-013-R7, R8, S3, S5) — Verified 2026-11-13: PermissionAuditUITests 5/5 pass with the microphone revoked (`simctl privacy revoke`, `TEST_RUNNER_FILE013_MIC_REVOKED=1`): microphone real denial 7.7 s, camera restricted 17.3 s, Local Network denied 14.2 s, screen capture restricted 5.0 s and denied 5.3 s; negative control: with the permission reset and the variable set the microphone test fails (explainer shown); without the variable it skips
- [X] FILE-013-T08 [US1] [US2] Run on an own iOS 27.2 simulator: unit tests, `PermissionAuditUITests`
  with the microphone revoked, `CameraUITests`, `OSCReceiverUITests`, `GuidedFirstSceneUITests`,
  `StatusUITests/testStartFailureMessagesAndActions`; PosterBoard count before and after
  (FILE-013-R11, S1, S5) — Verified 2026-11-13: unit 357/357; PermissionAuditUITests 5/5; CameraUITests 2, OSCReceiverUITests 1, OSCNetworkAccessUITests 1, GuidedFirstSceneUITests 4, `StatusUITests/testStartFailureMessagesAndActions` 1: 9/9 pass (172.6 s); PosterBoard reports 32 before and after

## Phase 3: US3 — one place, checked (P2)

- [X] FILE-013-T09 [US3] `scripts/check_permission_catalog.py` (plan D10) and
  `PermissionCatalogCheckTests` in `scripts/test_scripts.py`: repository OK; missing entry, extra key,
  changed text, Photos key, policy mismatch each fail (FILE-013-R6, S2, S4) — Verified 2026-11-13: `check_permission_catalog.py` OK on the repository (4 permissions, no Photos key); `python3 scripts/test_scripts.py PermissionCatalogCheckTests` 8 tests pass (0.007 s): repository OK, extra key, missing key, changed text, both Photos keys, policy missing and extra name each fail
- [X] FILE-013-T10 [US3] `docs/privacy-policy.md` "Permissions and why" matches the catalog exactly
  (names, timing, denied/restricted behaviour, Photos needs none); CI docs job runs the check
  (`.github/workflows/ios-ci.yml`) (FILE-013-R10) — Verified 2026-11-13: privacy policy section rewritten; the check passes on it and fails when a bullet is removed or added (tests above); CI docs-job step added (runs on the next push)
- [ ] FILE-013-T11 {device} D1: deny Microphone, Camera and Local Network in Settings and use each
  feature; restrict Camera with Screen Time and use the Camera visual; notices match the catalog
  (FILE-013-R9)

## Phase 4: Polish

- [X] FILE-013-T12 Gates: `check_compliance.py`, `validate_docs.py`, `test_scripts.py`,
  `check_permission_catalog.py`, `check_privacy_manifest.py` on the Debug simulator app; spec status
  and audit "after" column (FILE-013-R11) — Verified 2026-11-13: `check_compliance.py` OK, `validate_docs.py` OK (716 files), `test_scripts.py` 142 tests OK (1 skipped), `check_permission_catalog.py` OK, `check_privacy_manifest.py` OK on the Debug simulator app

## Dependencies

T01 → T02-T06. T03-T06 → T07 → T08. T01 → T09 → T10. Everything → T12. T11 needs D1 and the owner.
Parallel: T02 with T03-T06 (different files); T09 with T03-T08.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: every requirement maps to a task (R1-R2 T01; R3 T03, T05; R4 T04, T05; R5 T02; R6 T09; R7
T07; R8 T06-T07; R9 T11; R10 T10; R11 T08, T12) and every success criterion to a verifying task (S1
T02, T07-T08; S2 T09; S3 T07-T08; S4 T09; S5 T08). Two fixes applied to the spec: the "who owns the
texts" clarification now matches plan D2 (the catalog references contract-fixed texts and owns only
the Local Network text), and FILE-013-R1's "in-app name" is the privacy policy's bullet name, as the
check script (D10) uses it. No constitution conflicts (no new prompt, key or networking); no ambiguous
terms left.
