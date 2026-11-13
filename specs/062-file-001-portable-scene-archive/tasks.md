# Tasks: FILE-001 Portable Scene Archive

**Input**: Design documents from `specs/062-file-001-portable-scene-archive/` (spec, plan, research,
data-model, contracts/scene-archive.md, quickstart)

**Tests**: requested by the spec (S1-S4) and owner rule 7 budgets (unit ≈ 1-2 s and ≤ 10 s, suite
< 1 min). Tick a task `[X]` only when verified, with " — Verified <date>: <how>". Simulator tasks
use the agent's own `FILE1 iPhone 17` (iOS 27.2) simulator through `xcodebuild` only.

Format: `- [ ] FILE-001-Tnn [P?] [Story?] Description with file path`

## Phase 1: Setup

- [ ] FILE-001-T01 Create `Packages/SceneArchive/Package.swift` (tools 6.0, iOS 26 / macOS 15; dependencies `../LocalPortability`, `../SceneFormat`, `../Compositor`, `../ParameterGraph`, tests also `../VisualGenerators`; library target `SceneArchive` depending on `LocalPortability`, `SceneFormat`, `Compositor` (MediaSniffing, GeneratorGraphImport) and `ParameterGraph`) with a header comment citing FILE-001, and add `SceneArchive` to the 5 package loops in `.github/workflows/ios-ci.yml`

## Phase 2: Foundational (blocks all stories)

- [ ] FILE-001-T02 [P] Make `ExecutableSignature`, its `Verdict` and `classify(_:)` public in `Packages/Compositor/Sources/GeneratorGraphImport/ExecutableSignature.swift` (no behavior change; SHD-011 tests still pass)
- [ ] FILE-001-T03 [P] Refuse ZIP entries whose Unix mode is a symbolic link or another non-regular type (`unsupported("symbolic links or special files")`) in `Packages/LocalPortability/Sources/LocalPortability/StoredZip.swift`, with tests in `Packages/LocalPortability/Tests/LocalPortabilityTests/StoredZipTests.swift` (link refused, regular and attribute-less entries accepted)
- [ ] FILE-001-T04 Format constants and limits (format `projectm-ios.scene-archive`, version 1, `scene.json`, `assets/`, extension `pmscene`, type identifier `org.projectmios.scene-archive`, 600,000,000-byte archive, 3 files, 64 KiB manifest, photo 40 MiB, video 500 MiB) in `Packages/SceneArchive/Sources/SceneArchive/SceneArchiveFormat.swift`; manifest model (`assets` records: key, type `photo`/`video`, path `assets/<key>.<ext>`) in `SceneArchiveManifest.swift`; `SceneArchiveError` with the contract §4 cases and messages in `SceneArchiveError.swift`
- [ ] FILE-001-T05 Content check in `Packages/SceneArchive/Sources/SceneArchive/SceneArchiveContentCheck.swift`: SHD-011 signature on the first 64 KiB (`executableContent`, `nestedArchive`), then `png`/`jpg` via `ImageHeaderSniffer` (container must match), `mov` via `MovieContainerSniffer` (`wrongContent`), and the per-type size (`assetTooLarge`)
- [ ] FILE-001-T06 `SceneDocument.remappingStoreIDs(_:)` in `Packages/SceneArchive/Sources/SceneArchive/SceneStoreRemapping.swift` (photo/video store IDs only; keys and `extra` kept)

## Phase 3: User Story 1 — A scene with its media moves to a clean install intact (P1, MVP)

**Goal**: export → import into empty stores resolves every asset. **Independent test**: package round trip, then the app service on the simulator with fresh temporary stores.

- [ ] FILE-001-T07 [US1] `SceneArchiveWriter` in `Packages/SceneArchive/Sources/SceneArchive/SceneArchiveWriter.swift`: refuse documents with validation errors, media not matching the document's photo/video assets, or more than one photo/video; write `scene.json`, assets by key, then the sorted-keys manifest through `PortableArchiveWriter`
- [ ] FILE-001-T08 [US1] `SceneArchiveReader` in `Packages/SceneArchive/Sources/SceneArchive/SceneArchiveReader.swift`: size, PortableArchive read, manifest keys, records vs. document assets, unexpected files, content checks, SCN-001 decode and validation (errors refuse), returning `SceneArchiveContents`
- [ ] FILE-001-T09 [US1] Package round-trip tests in `Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveRoundTripTests.swift`: fixture (photo PNG, movie bytes, text, generator graph) → bytes → read: equal document, identical media bytes, exact layout and manifest, two exports with a fixed date byte-identical, scene without media gives manifest + scene only, remapping test (only store IDs change)
- [ ] FILE-001-T10 [US1] Split `PhotoStore.importImage` into `stage(at:)` + `adopt(_:)` + `makeCurrent(_:)` in `Apps/projectM-iOS/Coordinators/PhotoStore.swift` and the same for `VideoStore.importVideo` in `Apps/projectM-iOS/Coordinators/VideoStore.swift`, behavior of the existing imports unchanged
- [ ] FILE-001-T11 [US1] `SceneArchiveService` in `Apps/projectM-iOS/Coordinators/SceneArchiveService.swift`: `export(_:modified:)` (media from the stores only, temporary `projectM-iOS Scene <date>.pmscene`, leftovers cleared) and `cleanUpExport()`; `importArchive(at:)` (scope + coordinated size check and mapped read, reader, staging stores in a per-import temporary folder, remap, validate against staged IDs, commit: move, switch identifiers, delete previous; staging removed always); add `SceneArchive` to `project.yml`
- [ ] FILE-001-T12 [US1] App tests in `Apps/projectM-iOS/Tests/SceneArchiveServiceTests.swift`: clean-install round trip (source stores with a PNG photo and the DEBUG fixture movie; target empty stores in another temporary folder): every reference resolves, scene equals original after remapping, photo decodes (ImageIO) and video has a video track (AVFoundation); export refuses a missing photo; temporary export removed by cleanup

## Phase 4: User Story 2 — A hostile or damaged archive changes nothing (P1)

**Goal**: every hostile archive is refused with its reason and no store change. **Independent test**: the hostile table.

- [ ] FILE-001-T13 [US2] Hostile table in `Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveHostileTests.swift` (hand-built ZIPs): `../x`, absolute path, symbolic link entry, duplicate name (case), too many entries, oversized entry, nested ZIP asset, Mach-O asset, script asset, JPEG named `.png`, manifest/scene mismatch (record without asset, asset without record, type differs), wrong record path, missing asset file, extra unlisted file, extra listed file, newer version, wrong format, scene refused, scene with errors, two photos, archive over the size limit — each with its exact `SceneArchiveError`
- [ ] FILE-001-T14 [US2] App atomicity tests in `Apps/projectM-iOS/Tests/SceneArchiveServiceTests.swift`: stores already holding a photo and video; (a) a hostile archive (Mach-O asset) and (b) an archive whose video (the last asset) fails the store's import (video store limit below the file size) both leave the stores' files and identifiers byte-for-byte unchanged and no staging folder; (c) a successful import replaces both and reports `replacedPhoto`/`replacedVideo`
- [ ] FILE-001-T15 [P] [US2] Source-safety test in `Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveSourceSafetyTests.swift`: no networking, file, process or dynamic-loading API in the package sources

## Phase 5: Polish & Cross-Cutting

- [ ] FILE-001-T16 ADR (next free number) `docs/adr/00NN-scene-archive-format.md` (format, limits, refusals, staging commit, store model, no screen) and `docs/adr/README.md` index entry
- [ ] FILE-001-T17 [P] Privacy review: `docs/privacy-policy.md` (scene archives hold the user's own scene, photo and video; created and shared only by the user; nothing uploaded), privacy section in `docs/test-reports/scene-archive.md`, `python3 scripts/check_privacy_manifest.py` on the Debug simulator app
- [ ] FILE-001-T18 Linux shape and host runs: `swift test` for SceneArchive, LocalPortability, Compositor (GeneratorGraphImport tests) with and without `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`; app tests on the simulator; `check_compliance.py`, `validate_docs.py`; PosterBoard report count before/after; results in `docs/test-reports/scene-archive.md`
- [ ] FILE-001-T19 {device} Export a scene archive on D1, send it by AirDrop or Files to D3, import there offline: the photo and video appear (needs the SCN-014 entry point or a DEBUG build calling the service; owner)

## Dependencies

T01 → T02-T06 → US1 (T07, T08 → T09; T10 → T11 → T12) → US2 (T13 needs T08; T14 needs T11) → T16-T18. T19 waits for SCN-014.

## Parallel opportunities

T02, T03 (different packages); T09 and T13 (different test files) once T07/T08 exist; T15, T17.

## Implementation strategy

MVP = US1 (package round trip + app clean-install round trip). US2 hardens the same reader and
service. No screen in this row.
