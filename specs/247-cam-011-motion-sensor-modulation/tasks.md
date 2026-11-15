# Tasks: CAM-011 Motion Sensor Modulation

**Input**: Design documents from `specs/247-cam-011-motion-sensor-modulation/` (spec, plan, research, data-model,
contracts/motion-sources.md, quickstart).

**Tests**: requested by the spec (acceptance: "Synthetic motion stream produces bounded normalized values";
CAM-011-S1 to S5). Budgets (owner rule 7): unit test ≤ 2 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] CAM-011-T01 Create the private simulator "CAM11 iPhone 17" (iOS 27.2), count PosterBoard reports, run `xcodegen generate` in the worktree — Verified 2026-11-14: simulator 68D51891 created, PosterBoard 27 reports before, `xcodegen generate` OK

## Phase 2: Foundational (package)

- [X] CAM-011-T02 Add `MotionAxis`, `MotionSample`, `MotionRange` ("narrow (20°), medium (45°, default), wide (90°)"), `MotionFeatureValues` (neutral 0.5/0.5/0.5/0) and `MotionTracker` (unwrap with offsets limited to ±2π, calibrate, restart, 60 ms smoothing, shake |a|/2 g through attack 20 ms / release 300 ms, Δt cap 0.25 s, no allocation) in `Packages/ParameterGraph/Sources/ParameterGraph/MotionTracker.swift` — Verified 2026-11-14: `swift test` ParameterGraph 187 + 51 tests pass (MotionTrackerTests 10)
- [X] CAM-011-T03 Add `AudioFeatureSource.motion(MotionAxis)` (IDs `audio.motion.<axis>`, parse, value from `AudioFeatureFrame.motion`, nil → neutral) in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift`; refuse the names in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift` and map the case to an unreachable constant in `ExpressionCompiler.swift` — Verified 2026-11-14: ExpressionRejectionTests.testMotionSourcesAreNotFormulaNames, MotionTrackerTests.testMotionSourceIDsRoundTrip

## Phase 3: User Story 1 - Tilt to play a parameter (P1) 🎯 MVP

**Goal**: attitude sources normalized around a calibrated neutral, bounded for any stream.
**Independent Test**: `swift test --package-path Packages/ParameterGraph --filter Motion`.

- [X] CAM-011-T04 [US1] Synthetic-stream acceptance tests in `Packages/ParameterGraph/Tests/ParameterGraphTests/MotionTrackerTests.swift`: sweeps beyond range, spikes, NaN/±∞, time standing still/backwards, yaw seam crossed both ways (< 0.01 per sample), calibration → 0.5, range endpoints, restart re-anchors, ID round trip and expression refusal (S1, S2, S5); plus a scene round trip of a motion binding in `Packages/SceneFormat/Tests/SceneFormatTests/SceneMotionSourceTests.swift` (MOD-013 path) — Verified 2026-11-14: MotionTrackerTests (10 tests, 0.009 s; the acceptance testSyntheticMotionStreamProducesBoundedNormalizedValues checks 2,000 samples × 4 values) and SceneMotionSourceTests on the host
- [X] CAM-011-T05 [US1] App sensor layer: `MotionSampling` protocol, `CoreMotionSampler` (CMMotionManager device motion, `.xArbitraryZVertical`, main queue) and DEBUG `StandInMotionSampler` in `Apps/projectM-iOS/Coordinators/MotionSampling.swift` — Verified 2026-11-14: build-for-testing on CAM11 iPhone 17 succeeded with no warnings in the new files
- [X] CAM-011-T06 [US1] `MotionModulationCoordinator` (demand = available ∧ active ∧ (host uses motion ∨ readout open); 60 Hz or 30 Hz under a 30 fps power budget; calibrate with announcement; range preference `settings.motion.range` written on change only, removed by `-uitestResetNotice`) in `Apps/projectM-iOS/Coordinators/MotionModulationCoordinator.swift` — Verified 2026-11-14: MotionModulationAppTests.testReadoutRateRangeAndUnavailableDevice
- [X] CAM-011-T07 [US1] Host and app wiring: `usesMotion`, `motionValues`, `onMotionDemandChange` in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`; `connectMotion(host)` in `Apps/projectM-iOS/Coordinators/AppCoordinator+Motion.swift`; the lazy property, the `connectMotion` call and the `sceneBecame(active:)` hook in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; inspector names in `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift` — Verified 2026-11-14: MotionModulationAppTests.testPitchBindingDrivesTheGlowAndTheSensorFollowsDemand (1.3 s)
- [X] CAM-011-T08 [US1] App test `Apps/projectM-iOS/Tests/MotionModulationAppTests.swift`: a pitch binding drives the glow from an injected sampler; sampling stops on background and on unbind; 30 Hz under Battery saver; names (S3) — Verified 2026-11-14: MotionModulationAppTests, 2 tests pass on CAM11 iPhone 17 (iOS 27.2)

## Phase 4: User Story 2 - Shake (P2)

- [X] CAM-011-T09 [US2] Shake envelope tests in `MotionTrackerTests.swift` (still → 0, rapid shakes bounded, rise within a few samples, fall after stop) and a threshold trigger accepting `audio.motion.shake` — Verified 2026-11-14: MotionTrackerTests.testShakeRisesQuicklyAndFallsBack, testThresholdTriggerAcceptsShake

## Phase 5: User Story 3 - Calibrate and range in Settings (P2)

- [X] CAM-011-T10 [US3] `MotionModulationSection` (readout as accessibility elements, ≤ 10 Hz; Calibrate; Range; unavailable note disabling both) in `Apps/projectM-iOS/Views/MotionModulationSection.swift`, added to `performanceSection` in `Apps/projectM-iOS/Views/SettingsView.swift` with id "motion" — Verified 2026-11-14: MotionCalibrationUITests (readout identifiers and values), build with the type-check flags: no warning in the section
- [X] CAM-011-T11 [US3] UI test `Apps/projectM-iOS/UITests/MotionCalibrationUITests.swift`: with `-uitestMotionStandIn`, the readout shows a tilt, Calibrate brings "Tilt forward" to 50 % (S4, < 30 s) — Verified 2026-11-14: MotionCalibrationUITests passed in 13.9 s on CAM11 iPhone 17

## Phase 6: Polish & cross-cutting

- [X] CAM-011-T12 The new key in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` (included keys), `scripts/run_device_tests.py` (`ALLOWED_KEYS`), `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`; run `LibraryBackupAppTests` and the LibraryBackup package tests — Verified 2026-11-14: LibraryBackupAppTests 5 pass (testIncludedKeysAndFolderNamesAgreeWithTheStores), LibraryBackup package 86 tests pass
- [X] CAM-011-T13 Privacy policy "Device motion" section in `docs/privacy-policy.md`; ADR `docs/adr/00NN-device-motion-modulation.md` — Verified 2026-11-14: docs/privacy-policy.md "Device motion", ADR-0065; validate_docs OK
- [X] CAM-011-T14 Repo checks, the Linux shape of ParameterGraph (no CoreMotion import in packages: `grep`), (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the built app, type-check budget, PosterBoard count; delete the simulator and derived data — Verified 2026-11-14: compliance, validate_docs, motion policy, permission catalog (5 permissions, unchanged), status events OK; 179 script tests OK; check_privacy_manifest and check_network_symbols OK on the Debug app; no CoreMotion in Packages
- [ ] CAM-011-T15 {device} On D1: bind a scene's glow to Tilt forward and Shake, Calibrate, tilt and shake; background the app and confirm the sensor stops

## Dependencies

T01 → T02 → T03 → T04; T05 → T06 → T07 → T08; T09 after T02; T10 after T06 → T11; T12-T14 last. US2 and US3 depend
on the foundation only. Parallel: T04/T05 (different files), T12/T13.

## Implementation Strategy

MVP = Phases 1-3 (package acceptance plus the app binding path); then shake tests, Settings, polish.
