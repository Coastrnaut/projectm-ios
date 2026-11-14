# Tasks: CAM-008 Person Silhouette Mask

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/person-mask.md
Tests are written with the code they prove (short tests, owner rule 7).

## Phase 1: Foundation (plain Swift, Linux-buildable)

- [ ] CAM-008-T01 `PersonMask.swift`: `CameraPersonMaskMode`, `PersonMaskBitmap` (+ rectangle fixture), `PersonSegmentationQuality`, `PersonMaskPlan`/`PersonMaskPolicy` (D6), `PersonMaskAvailability`, `PersonMaskSchedule` (D4) in `Packages/Compositor/Sources/CameraLayer/`
- [ ] CAM-008-T02 `PersonMaskTests` (policy table, schedule stride/in-flight, bitmap validation, mode raw values) in `Packages/Compositor/Tests/CompositorTests/PersonMaskTests.swift`

## Phase 2: Segmentation and masking (US1, US2)

- [ ] CAM-008-T03 `PersonSegmenting.swift`: protocol (C1), `VisionPersonSegmenter` (D1, D2), `FixturePersonSegmenter`
- [ ] CAM-008-T04 `PersonMasker.swift` (C2): schedule, utility serial queue (injectable runner), newest-mask slot (try-lock), availability, reset
- [ ] CAM-008-T05 Masker tests: at most one in flight, stride 2/3, failing → `failed` sticky, unsupported, paused plan, reset drops the mask
- [ ] CAM-008-T06 `CameraLayerSource` (C3): mask mode, r8 upload ring, uniforms (`maskMode`, `maskSpace`), shader coverage term (D3)
- [ ] CAM-008-T07 [US1] GPU acceptance `PersonMaskLayerTests`: fixture mask → alpha 0 outside, unmasked pixels inside within 1/255 for rotation/mirror/Fill-Fit-anchor-zoom cases, texture and upright spaces, Background inverse (S1)
- [ ] CAM-008-T08 [US2] GPU acceptance: unsupported, failing and paused segmenters and no-mask-yet render equal to Off within 1/255 (S2)
- [ ] CAM-008-T09 Providers (C4): `personMasker` hook; AV provider offers pixel buffers; stand-in offers its picture
- [ ] CAM-008-T10 Vision probe test on a synthetic still (records whether it runs on this host/Simulator; never evidence)

## Phase 3: App (US1-US3)

- [ ] CAM-008-T11 `AppSettings.cameraPersonMask` + key in `allKeys`, FILE-005 included keys, `run_device_tests.py` ALLOWED_KEYS
- [ ] CAM-008-T12 `CameraVisualHost`: masker creation (Vision or `-uitestPersonSegmenter`), policy updates with the quality notifications, mode forwarding; coordinator availability mirror and settings forwarding
- [ ] CAM-008-T13 `CameraPersonMaskRow` (C5) + SettingsView/VisualizerView one-line wiring
- [ ] CAM-008-T14 App unit tests `CameraPersonMaskTests` (setting round-trip, notes per availability, host draws masked/unmasked) and `LibraryBackupAppTests`
- [ ] CAM-008-T15 UI test `CameraPersonMaskUITests`: fixture → picker enabled; unsupported → disabled with note

## Phase 4: Polish

- [ ] CAM-008-T16 {device} D1: person masked in Person and Background, alignment through rotation/mirror/crop, ≥30 fps, mask space confirmed (quickstart)
- [ ] CAM-008-T17 ADR-0063 (privacy and performance of on-device segmentation); repo checks (compliance, docs, motion, permission catalog, status events, script tests, privacy manifest, network symbols); type-check budget

## Dependencies

T01 → T02, T03 → T04 → T05; T04 + T06 → T07, T08; T09 after T04; T11 → T12 → T13 → T14, T15; T17 last.
