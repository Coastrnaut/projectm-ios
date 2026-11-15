# Tasks: CAM-011 Motion Sensor Modulation

**Input**: Design documents from `specs/247-cam-011-motion-sensor-modulation/` (spec, plan, research, data-model,
contracts/motion-sources.md, quickstart).

**Tests**: requested by the spec (acceptance: "Synthetic motion stream produces bounded normalized values";
CAM-011-S1 to S5). Budgets (owner rule 7): unit test ≤ 2 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [ ] CAM-011-T01 Create the private simulator "CAM11 iPhone 17" (iOS 27.2), count PosterBoard reports, run `xcodegen generate` in the worktree

## Phase 2: Foundational (package)

- [ ] CAM-011-T02 Add `MotionAxis`, `MotionSample`, `MotionRange` ("narrow (20°), medium (45°, default), wide (90°)"), `MotionFeatureValues` (neutral 0.5/0.5/0.5/0) and `MotionTracker` (unwrap with offsets limited to ±2π, calibrate, restart, 60 ms smoothing, shake |a|/2 g through attack 20 ms / release 300 ms, Δt cap 0.25 s, no allocation) in `Packages/ParameterGraph/Sources/ParameterGraph/MotionTracker.swift`
- [ ] CAM-011-T03 Add `AudioFeatureSource.motion(MotionAxis)` (IDs `audio.motion.<axis>`, parse, value from `AudioFeatureFrame.motion`, nil → neutral) in `Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift`; refuse the names in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift` and map the case to an unreachable constant in `ExpressionCompiler.swift`

## Phase 3: User Story 1 - Tilt to play a parameter (P1) 🎯 MVP

**Goal**: attitude sources normalized around a calibrated neutral, bounded for any stream.
**Independent Test**: `swift test --package-path Packages/ParameterGraph --filter Motion`.

- [ ] CAM-011-T04 [US1] Synthetic-stream acceptance tests in `Packages/ParameterGraph/Tests/ParameterGraphTests/MotionTrackerTests.swift`: sweeps beyond range, spikes, NaN/±∞, time standing still/backwards, yaw seam crossed both ways (< 0.01 per sample), calibration → 0.5, range endpoints, restart re-anchors, ID round trip and expression refusal (S1, S2, S5)
- [ ] CAM-011-T05 [US1] App sensor layer: `MotionSampling` protocol, `CoreMotionSampler` (CMMotionManager device motion, `.xArbitraryZVertical`, main queue) and DEBUG `StandInMotionSampler` in `Apps/projectM-iOS/Coordinators/MotionSampling.swift`
- [ ] CAM-011-T06 [US1] `MotionModulationCoordinator` (demand = available ∧ active ∧ (host uses motion ∨ readout open); 60 Hz or 30 Hz under a 30 fps power budget; calibrate with announcement; range preference `settings.motion.range` written on change only, removed by `-uitestResetNotice`) in `Apps/projectM-iOS/Coordinators/MotionModulationCoordinator.swift`
- [ ] CAM-011-T07 [US1] Host and app wiring: `usesMotion`, `motionValues`, `onMotionDemandChange` in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`; `connectMotion(host)` in `Apps/projectM-iOS/Coordinators/AppCoordinator+Motion.swift`; the lazy property, the `connectMotion` call and the `sceneBecame(active:)` hook in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; inspector names in `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift`
- [ ] CAM-011-T08 [US1] App test `Apps/projectM-iOS/Tests/MotionModulationAppTests.swift`: a pitch binding drives the glow from an injected sampler; sampling stops on background and on unbind; 30 Hz under Battery saver; names (S3)

## Phase 4: User Story 2 - Shake (P2)

- [ ] CAM-011-T09 [US2] Shake envelope tests in `MotionTrackerTests.swift` (still → 0, rapid shakes bounded, rise within a few samples, fall after stop) and a threshold trigger accepting `audio.motion.shake`

## Phase 5: User Story 3 - Calibrate and range in Settings (P2)

- [ ] CAM-011-T10 [US3] `MotionModulationSection` (readout as accessibility elements, ≤ 10 Hz; Calibrate; Range; unavailable note disabling both) in `Apps/projectM-iOS/Views/MotionModulationSection.swift`, added to `performanceSection` in `Apps/projectM-iOS/Views/SettingsView.swift` with id "motion"
- [ ] CAM-011-T11 [US3] UI test `Apps/projectM-iOS/UITests/MotionCalibrationUITests.swift`: with `-uitestMotionStandIn`, the readout shows a tilt, Calibrate brings "Tilt forward" to 50 % (S4, < 30 s)

## Phase 6: Polish & cross-cutting

- [ ] CAM-011-T12 The new key in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` (included keys), `scripts/run_device_tests.py` (`ALLOWED_KEYS`), `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`; run `LibraryBackupAppTests` and the LibraryBackup package tests
- [ ] CAM-011-T13 Privacy policy "Device motion" section in `docs/privacy-policy.md`; ADR `docs/adr/00NN-device-motion-modulation.md`
- [ ] CAM-011-T14 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the built app, type-check budget, PosterBoard count; delete the simulator and derived data
- [ ] CAM-011-T15 {device} On D1: bind a scene's glow to Tilt forward and Shake, Calibrate, tilt and shake; background the app and confirm the sensor stops

## Dependencies

T01 → T02 → T03 → T04; T05 → T06 → T07 → T08; T09 after T02; T10 after T06 → T11; T12-T14 last. US2 and US3 depend
on the foundation only. Parallel: T04/T05 (different files), T12/T13.

## Implementation Strategy

MVP = Phases 1-3 (package acceptance plus the app binding path); then shake tests, Settings, polish.
