# Tasks: CAM-008 Person Silhouette Mask

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/person-mask.md
Tests are written with the code they prove (short tests, owner rule 7).

## Phase 1: Foundation (plain Swift, Linux-buildable)

- [X] CAM-008-T01 `PersonMask.swift`: `CameraPersonMaskMode`, `PersonMaskBitmap` (+ rectangle fixture), `PersonSegmentationQuality`, `PersonMaskPlan`/`PersonMaskPolicy` (D6), `PersonMaskAvailability`, `PersonMaskSchedule` (D4) in `Packages/Compositor/Sources/CameraLayer/` — Verified 2026-11-14: `swift test --filter PersonMask` (PersonMaskTests 3 pass) and the Linux-shape build (`-DCOMPOSITOR_NO_METAL`)
- [X] CAM-008-T02 `PersonMaskTests` (policy table, schedule stride/in-flight, bitmap validation, mode raw values) in `Packages/Compositor/Tests/CompositorTests/PersonMaskTests.swift` — Verified 2026-11-14: PersonMaskTests 3/3 pass on the Mac host and the iOS 27.2 Simulator

## Phase 2: Segmentation and masking (US1, US2)

- [X] CAM-008-T03 `PersonSegmenting.swift`: protocol (C1), `VisionPersonSegmenter` (D1, D2), `FixturePersonSegmenter` — Verified 2026-11-14: PersonMaskerTests and PersonMaskLayerTests use FixturePersonSegmenter; VisionPersonSegmenter exercised by T10
- [X] CAM-008-T04 `PersonMasker.swift` (C2): schedule, utility serial queue (injectable runner), newest-mask slot (try-lock), availability, reset — Verified 2026-11-14: PersonMaskerTests 5/5 pass (host and Simulator)
- [X] CAM-008-T05 Masker tests: at most one in flight, stride 2/3, failing → `failed` sticky, unsupported, paused plan, reset drops the mask (R7); the masker source uses no file, URL or logging API (S4, checked by a source scan in the test) — Verified 2026-11-14: PersonMaskerTests: stride 2/3, one in flight, stale result dropped, failure sticky, unsupported never called, warm pause, source scan
- [X] CAM-008-T06 `CameraLayerSource` (C3): mask mode, r8 upload ring, uniforms (`maskMode`, `maskSpace`), shader coverage term (D3) — Verified 2026-11-14: PersonMaskLayerTests 2/2 pass; a mutation (upright mask sampled as texture) made 4 assertions fail
- [X] CAM-008-T07 [US1] GPU acceptance `PersonMaskLayerTests`: fixture mask → alpha 0 outside, unmasked pixels inside within 1/255 for rotation/mirror/Fill-Fit-anchor-zoom cases, texture and upright spaces, Background inverse (S1) — Verified 2026-11-14: PersonMaskLayerTests.testFixtureMaskCutsTheLayerToThePersonInEveryFraming (4 framings × Person/Background, within 1/255) on host and Simulator
- [X] CAM-008-T08 [US2] GPU acceptance: unsupported, failing and paused segmenters and no-mask-yet render equal to Off within 1/255 (S2) — Verified 2026-11-14: PersonMaskLayerTests.testUnavailableSegmentationDrawsTheUnmaskedPicture (none, unsupported, failing, paused, no mask yet = Off within 1/255)
- [X] CAM-008-T09 Providers (C4): `personMasker` hook; AV provider offers pixel buffers; stand-in offers its picture — Verified 2026-11-14: AV provider builds for the iOS Simulator SDK (app build); stand-in path exercised by every layer and app test
- [X] CAM-008-T10 Vision probe test on a synthetic still (records whether it runs on this host/Simulator; never evidence) — Verified 2026-11-14: VisionPersonSegmenterProbeTests: Mac host ran (mask 384×512, upright for a quarter turn); iOS 27.2 Simulator threw "E5RT is not supported", so the Simulator reports unsupported. Not device evidence

## Phase 3: App (US1-US3)

- [X] CAM-008-T11 `AppSettings.cameraPersonMask` + key in `allKeys`, FILE-005 included keys, `run_device_tests.py` ALLOWED_KEYS — Verified 2026-11-14: CameraPersonMaskTests.testChoiceDefaultsPersistsAndIsBackedUp, SettingsTests 9/9, LibraryBackupAppTests 5/5, LibraryBackup package 83/83
- [X] CAM-008-T12 `CameraVisualHost`: masker creation (Vision or `-uitestPersonSegmenter`), policy updates with the quality notifications, mode forwarding; coordinator availability mirror and settings forwarding — Verified 2026-11-14: CameraPersonMaskTests host tests (masked corner black for Person, red for Background, unsupported and failing draw full picture, no restart)
- [X] CAM-008-T13 `CameraPersonMaskRow` (C5; label "Person mask", values, note as hint: R8) + SettingsView/VisualizerView one-line wiring — Verified 2026-11-14: CameraPersonMaskUITests 2/2 (label, values, disabled with note)
- [X] CAM-008-T14 App unit tests `CameraPersonMaskTests` (setting round-trip, notes per availability, host draws masked/unmasked) and `LibraryBackupAppTests` — Verified 2026-11-14: CameraPersonMaskTests 5/5, LibraryBackupAppTests 5/5, CameraCropTests 4/4 on the CAM8 iPhone 17 (iOS 27.2) Simulator
- [X] CAM-008-T15 UI test `CameraPersonMaskUITests`: fixture → picker enabled; unsupported → disabled with note — Verified 2026-11-14: CameraPersonMaskUITests 2/2 (25.2 s, 19.9 s) on the CAM8 iPhone 17 Simulator

## Phase 4: Polish

- [ ] CAM-008-T16 {device} D1: person masked in Person and Background, alignment through rotation/mirror/crop, ≥30 fps, mask space confirmed (quickstart)
- [X] CAM-008-T17 ADR-0063 (privacy and performance of on-device segmentation); repo checks (compliance, docs, motion, permission catalog, status events, script tests, privacy manifest, network symbols); type-check budget — Verified 2026-11-14: ADR-0063; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 177 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no new type-check warnings

## Dependencies

T01 → T02, T03 → T04 → T05; T04 + T06 → T07, T08; T09 after T04; T11 → T12 → T13 → T14, T15; T17 last.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 T06/T13; R2 T06/T07; R3 T07; R4 T04/T05; R5 T08/T13/T15; R6 T01/T02/T12; R7 T04/T05/T17;
R8 T13/T15; R9 T11/T14. S1 T07; S2 T08/T15; S3 T05; S4 T05/T17; S5 T16. Fixes applied: R8 named in T13,
S4's "no file written" given a test (T05). No conflicts with CAM-001…CAM-007 contracts (Off is the
CAM-007 arithmetic unchanged).
