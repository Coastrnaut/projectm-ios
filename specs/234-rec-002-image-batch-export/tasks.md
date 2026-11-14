# Tasks: REC-002 Image Batch Export

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/batch-export.md](contracts/batch-export.md)
**Tests**: requested by the roadmap acceptance and the brief (five fixture snapshots through the real renderer, tricky names, unchanged scene, cancel; UI test under 30 s).

## Phase 1: Foundational

- [X] REC-002-T01 [P] `SnapshotBatchNaming` (contract B1; research REC-002-D6): `safeName(_:)` keeps letters, marks and digits of any script, spaces, "-", "_", "(" and ")"; every other character becomes "-"; runs of "-" or spaces collapse; leading/trailing spaces, "-" and "." trimmed; "at most 48 characters"; empty → "Snapshot"; `fileNames(_:)` gives `<NN>-<name>.png` (NN 1-based, two digits) with " (2)"… on a case-insensitive repeat, in Apps/projectM-iOS/Coordinators/SnapshotBatchNaming.swift — Verified 2026-11-14: SnapshotBatchNamingTests 2 pass (12 safe-name cases incl. slashes, emoji, keycap, empty, CJK; 100-item padding and case-insensitive uniqueness)
- [X] REC-002-T02 [P] `SnapshotBatchSize` (1920 × 1080, 1080 × 1920, 1080 × 1080), `SnapshotRenderValues` (from a value map over a base; missing or wrong-kind values keep the base), `SnapshotBatchItem`, `SnapshotBatchJob` (data-model.md) and the job capture from the snapshot coordinator (live `read` overlaid with `SceneSnapshotRecallPlan` writes; refusals of contract B2) in Apps/projectM-iOS/Coordinators/SnapshotBatchJob.swift — Verified 2026-11-14: SnapshotBatchExportAcceptanceTests (values overlaid per snapshot: images differ where glow differs; refusals) on "REC2 iPhone 17" (iOS 27.2)
- [X] REC-002-T03 `SnapshotStillRenderer` (contract B3; research D2, D4): own device and queue; `NativeSpectrumHost.makeGenerator` (made internal) per item; `BloomEffect` + `EffectChain` when the clamped glow is not pass-through, the generator's `downstreamLuminance` set to the bloom's model; four frames at t = 1 s + n/60 s with the synthetic bands/waveform; blit to a shared buffer → `CapturedPixels(.sRGBBGRA8TopDown)` → PNG via `FrameImageEncoder`, in Apps/projectM-iOS/Visuals/SnapshotStillRenderer.swift and Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift — Verified 2026-11-14: testRenderingIsDeterministic (identical pixels twice, lit, linear differs) and the five-image acceptance test (PNGs of 1920 × 1080 through the real generator and bloom)

## Phase 2: User Story 1 — Export a set of looks (P1)

- [X] REC-002-T04 [US1] `SnapshotBatchExportCoordinator` (contract B4; research D1, D7): `start(selection:size:)` captures the job, deletes any previous batch folder, renders off the main actor into `<tmp>/SnapshotBatch/<UUID>/`, publishes progress, finishes with the file URLs; `done()` deletes the folder; leftovers removed at init; announcements on the library lane, in Apps/projectM-iOS/Coordinators/SnapshotBatchExportCoordinator.swift — Verified 2026-11-14: testFiveSnapshotsProduceFiveCorrectlyNamedPNGsAndChangeNothing (files in a batch folder, progress to finished, "Exported 5 images", Done deletes the folder)
- [X] REC-002-T05 [US1] Wiring: `AppCoordinator.snapshotBatch`, `connectSnapshotBatch()` (settings, snapshots, compare, announcer, photos, share simulation), the snapshot coordinator's weak `batchExport` link, in Apps/projectM-iOS/Coordinators/AppCoordinator+SnapshotBatch.swift, Apps/projectM-iOS/Coordinators/AppCoordinator.swift and Apps/projectM-iOS/Coordinators/SceneSnapshotCoordinator.swift — Verified 2026-11-14: app builds; SnapshotBatchExportUITests reaches the row through the app wiring
- [X] REC-002-T06 [US1] UI (contract B5): "Export Images…" row under the Compare row; the sheet with snapshot toggles, size picker, unsupported-visual notice, Export, progress and Cancel, then Save… (multi-document `fileExporter`), Share… (system sheet, REC-012 exclusions, DEBUG simulation), Save to Photos (REC-011 sequentially, "Saved N of M to Photos.") and Done; DEBUG probe, in Apps/projectM-iOS/Views/SnapshotBatchExportViews.swift and Apps/projectM-iOS/Views/SceneSnapshotRows.swift — Verified 2026-11-14: SnapshotBatchExportUITests (row, sheet, Export 5 Images, probe, status, Save… shown, Done); Save…/Share… system sheets not driven by UI tests
- [X] REC-002-T07 [US1] Acceptance tests in Apps/projectM-iOS/Tests/SnapshotBatchExportAcceptanceTests.swift: five fixture snapshots ("Dawn/Dusk", "Dawn:Dusk", "🌅🌅", "Sunset 🌅", "...") through the real renderer → exactly five files with the expected names, each a PNG of 1920 × 1080; scene file and backup bytes, snapshot entries, undo stack and live values unchanged, also with the scene locked (R9); a leftover folder is removed when a coordinator is created (R6); same snapshot twice → identical bytes (S4); naming unit tests in Apps/projectM-iOS/Tests/SnapshotBatchNamingTests.swift — Verified 2026-11-14: SnapshotBatchExportAcceptanceTests 4 pass (2.6 s): five tricky names → 01-Dawn-Dusk.png, 02-Dawn-Dusk.png, 03-Snapshot.png, 04-Sunset.png, 05-Snapshot.png, each PNG 1920 × 1080, exactly five files; scene file/backup bytes, snapshots, undo stack, live values unchanged with the scene locked

## Phase 3: User Story 2 — Cancel (P1)

- [X] REC-002-T08 [US2] Cancel and failure paths (research D9): the flag is checked before each image; afterwards the batch folder does not exist and nothing is offered; "Export cancelled" announced; acceptance test cancelling during the second image (injected per-image hook), in Apps/projectM-iOS/Coordinators/SnapshotBatchExportCoordinator.swift and Apps/projectM-iOS/Tests/SnapshotBatchExportAcceptanceTests.swift — Verified 2026-11-14: testCancelMidBatchLeavesNoFiles (cancel before image 2: phase cancelled, no folder, nothing offered, announced)

## Phase 4: User Story 3 — Choose snapshots and size (P2)

- [X] REC-002-T09 [US3] Selection in list order, square size, unusable rows not selectable, refusals (non-native visual, Compare active); Save to Photos with a stand-in that refuses after two images reports "Saved 2 of 5 to Photos." and keeps the batch (R8); acceptance test exporting two of five at Square → `01-…png`, `02-…png` of 1080 × 1080, in Apps/projectM-iOS/Tests/SnapshotBatchExportAcceptanceTests.swift — Verified 2026-11-14: testSelectionSizeRefusalsPhotosAndLeftovers (two of five at 1080 × 1080 in list order; "Saved 1 of 2 to Photos." with REC-011 failure notice; replace; refusals; leftover deleted)

## Phase 5: UI test

- [X] REC-002-T10 [US1] UI test under 30 s in Apps/projectM-iOS/UITests/SnapshotBatchExportUITests.swift: Circular Spectrum, five Save Snapshot taps, Export Images…, Export, the probe lists `01-Snapshot 1.png`…`05-Snapshot 5.png`, Done — Verified 2026-11-14: SnapshotBatchExportUITests passes in 28.7 s and 22.2 s on "REC2 iPhone 17" (iOS 27.2)

## Phase 6: Polish

- [X] REC-002-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), type-check budget, `LibraryBackupAppTests` (no new keys), privacy manifest and network symbol checks on the Debug app; spec status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 OK; no type-check warning in REC-002 files; LibraryBackupAppTests pass (no new keys); check_privacy_manifest OK and check_network_symbols OK on the Debug app

## Dependencies

T01, T02 parallel → T03 → T04 → T05 → T06 → T07, T08, T09 → T10 → T11.

## Implementation Strategy

MVP is US1 plus US2 (both P1). US3 uses the same coordinator with a smaller selection and another size.
