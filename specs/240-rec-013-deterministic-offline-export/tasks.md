# Tasks: REC-013 Deterministic Offline Export

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/offline-export.md](contracts/offline-export.md)
**Tests**: requested by the roadmap acceptance and the brief (two tiny exports with identical checksums, frame count = duration × fps, seed and audio changes alter them, cancel leaves no file; UI test under 30 s).

## Phase 1: Foundational (package, builds on Linux)

- [ ] REC-013-T01 [P] `OfflineFrameClock` (research REC-013-D1) and `OfflinePCMSource` (an in-memory `NormalizedPCMReader` whose readable end moves forward only) in Packages/VisualGenerators/Sources/VisualBandFeed/OfflineFrameClock.swift and OfflinePCMSource.swift
- [ ] REC-013-T02 [P] `OfflineFixtureAudio` (D6) and `OfflineExportManifest` (data-model; JSON with sorted keys, `sameFrames(as:)`) in Packages/VisualGenerators/Sources/VisualBandFeed/OfflineFixtureAudio.swift and OfflineExportManifest.swift
- [ ] REC-013-T03 `OfflineAnalysisDriver` (D2): pipeline with a fixed clock, `WaveformTap`, band and event subscriptions; `advance(toSample:)` returns the frame's bands, histories, kick and events, in Packages/VisualGenerators/Sources/VisualBandFeed/OfflineAnalysisDriver.swift
- [ ] REC-013-T04 Package tests (clock grid and counts, source limits, fixture repeatable and seed-dependent, manifest round trip, two drivers on the same audio give identical frames, different audio differs) in Packages/VisualGenerators/Tests/VisualGeneratorsTests/OfflineExportCoreTests.swift; Linux shape builds (`-Xswiftc -DVISUAL_NO_METAL`)

## Phase 2: User Story 1 and 2 — Repeatable export (P1)

- [ ] REC-013-T05 [US1] `OfflineExportJob` (data-model; REC-002 capture plus smoothing, Reduce Motion, size, rate, seed, audio source; refusals of contract C3) in Apps/projectM-iOS/Coordinators/OfflineExportJob.swift
- [ ] REC-013-T06 [US1] `OfflineAudioLoader` (R9: AVAudioFile → 44.1 kHz stereo Float32, at most 600 s, unreadable/too short errors) in Apps/projectM-iOS/Visuals/OfflineAudioLoader.swift
- [ ] REC-013-T07 [US1] `OfflineSceneRenderer` (contract C1, C2; D1, D4, D5, D7, D8): per-frame analysis, smoothing, events, generator + glow into a private texture, read-back + recorder copy in one command buffer, SHA-256, audio slices, sidecar, in Apps/projectM-iOS/Visuals/OfflineSceneRenderer.swift
- [ ] REC-013-T08 [US2] Acceptance tests (contract C2): two 2 s exports at 30 fps, 160 × 90 → identical checksum lists of 60, MP4 read back with 60 frames and an audio track, sidecar = manifest; Particle Fountain seed 1 vs 2 differ; Circular Spectrum fixture seed vs other audio differ; the live settings' values are unchanged after an export (R12, S5), in Apps/projectM-iOS/Tests/OfflineExportAcceptanceTests.swift

## Phase 3: User Story 1 and 3 — Sheet, cancel (P1, P2)

- [ ] REC-013-T09 [US1] `OfflineExportCoordinator` (contract C3; D9): phases, folder per export, leftovers at init, cancel, stop on leaving the foreground, Save to Photos (REC-011), announcements; wiring in Apps/projectM-iOS/Coordinators/OfflineExportCoordinator.swift, AppCoordinator+OfflineExport.swift, AppCoordinator.swift
- [ ] REC-013-T10 [US3] Cancel and refusal tests: cancel before frame 10 → no folder, phase cancelled; projectM refused; invalid seed refused; stop on background, in Apps/projectM-iOS/Tests/OfflineExportAcceptanceTests.swift
- [ ] REC-013-T11 [US1] UI (contract C4): row under the snapshot rows, the sheet (Audio, Choose File… via `fileImporter`, Seed, Shape, Rate, Export, progress, Cancel, Save…, Share…, Save to Photos, Done), in Apps/projectM-iOS/Views/OfflineExportViews.swift and Apps/projectM-iOS/Views/SettingsView.swift
- [ ] REC-013-T12 [US1] UI test (< 30 s): open the sheet, export 1 s of the fixture with `-uitestOfflineExportSeconds 1`, see "Exported 30 frames", Done, in Apps/projectM-iOS/UITests/OfflineExportUITests.swift

## Phase 4: Polish

- [ ] REC-013-T13 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network-symbol checks on the Debug app; type-check budget; LibraryBackup key test
- [ ] REC-013-T14 {device} On D1: export the fixture twice at Landscape 30 fps, compare the sidecars' `frameChecksums`, note render time and GPU name

## Dependencies

T01, T02 → T03 → T04; T05, T06 → T07 → T08; T07 → T09 → T10, T11 → T12; all → T13. T14 needs a person and D1.

## Analysis (speckit-analyze, 2026-11-14)

- Coverage: R1 T11; R2 T05; R3-R5 T03, T07; R6, R7 T07, T08; R8 T05, T10; R9 T06; R10 T09, T10; R11 T09, T11; R12 T08 (added: live values unchanged); R13 T09; R14 T13; R15 T09, T10. S1-S4 T08, T10; S5 T08; S6 T08 timing.
- No contradictions found between spec, plan and contract; terminology: "checksum sidecar" throughout.
