# Implementation Plan: QA-004 Scene Migration Matrix

**Branch**: `feature/qa-004` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/084-qa-004-scene-migration-matrix/spec.md`

## Summary

A data file, one runner per container and a meta-test:

1. **Matrix data** — `Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json`, a
   sibling of SCN-013's `manifest.json`: the containers (reader, test file, how each outcome
   surfaces), the test-only chains by name, the rows (version value as JSON text or missing, chain,
   shape, base fixtures, expected outcome, not-applicable containers with reasons) and the error
   table as data (`errors`: one entry per `SceneDecodeError` case; `migrationErrors`: one per
   `SceneMigrationError` case).
2. **Runners** — each reads `matrix.json` through `#filePath` and runs every row of its container
   through the real reader:
   - SceneFormat: `decode` (`SceneDocument.decode(_:migrator:)`) and `repairReport`
     (`SceneRepairReport.open(bytes:registry:migrator:)`), plus the meta-test.
   - ShowControl: `showStore` (`ShowStore.scene(_:)` and `ShowStore.load()` in a temporary folder).
   - SceneArchive: `archive` (`SceneArchiveReader.read(_:registry:limits:migrator:)`; the
     `migrator` parameter is new and defaults to `.standard`).
   - RenderGoldens: `golden` (`GoldenSceneRenderer.document(from:)` on Metal hosts;
     `SceneDocument.decode` with a note on Linux, where the harness is compiled out), base = the 7
     committed golden scenes.
   - projectM-iOSTests: `autosave` (`SceneAutosaveStore.load` in a temporary folder).
   Each runner checks that it executed exactly the cells the matrix assigns to it.
3. **Error table** — `contracts/scene-decode-errors.md` (human table) mirrors `matrix.json`
   `errors`; ADR-0028 gets a QA-004 amendment linking it and a "how to add a version" checklist.
4. **Meta-test** (`SceneMigrationMatrixMetaTests`): source scan of the `SceneDecodeError` and
   `SceneMigrationError` enums + a test-side exhaustive sample switch; every case has a data entry,
   a contract row and a sample whose SCN-012 report matches the entry; versions oldest…current,
   oldest−1, current+1, non-integer and missing have rows; every production step has a migrated row;
   every manifest version has a row; every container's test file exists and names the container;
   every not-applicable cell has a reason. Each check is also run on a deliberately broken in-memory
   copy to show it fails.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals, no main-actor mutation in
setUp/tearDown, no wall-clock assertions)
**Primary Dependencies**: SceneFormat (SCN-001, SCN-012, SCN-013), ShowControl/ShowStorage,
SceneArchive, RenderGoldens; XCTest; Foundation in tests only (`JSONDecoder` for the matrix)
**Storage**: Temporary folders in tests only
**Testing**: `swift test` per package (host and the Linux shape
`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`),
projectM-iOSTests on a dedicated simulator (`QA4 iPhone 17`, iOS 27.2) with `-only-testing`
**Target Platform**: iOS 26+ app; packages also macOS 15 and Linux
**Project Type**: Mobile app + Swift packages
**Performance Goals**: each new test < 10 s, package suites < 1 min (owner rule 7)
**Constraints**: SceneFormat sources keep Foundation in one file (source-safety test); no production
behaviour change except the archive reader's defaulted `migrator` parameter; no invented history
**Scale/Scope**: ~16 rows × 6 containers; 11 historical fixtures; 11 decode error cases

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | No new API use; tests only plus one defaulted parameter. Pass. |
| VI Modular boundaries | The matrix lives with SceneFormat's fixtures; other packages read the file (no new package dependency, no cycle). Pass. |
| X Evidence-based quality | Unit tests for deterministic logic; every cell is executed, not assumed. No device claim. Pass. |
| Privacy | Tests write only temporary folders; no logging added. Pass. |

No violations; no Complexity Tracking needed. Re-checked after design: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/084-qa-004-scene-migration-matrix/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/
    ├── migration-matrix.md       # matrix.json schema, containers, cell rules
    └── scene-decode-errors.md    # the documented error table
```

### Source Code (repository root)

```text
Packages/SceneFormat/Tests/SceneFormatTests/
├── Fixtures/legacy/matrix.json                  # new
├── SceneMigrationMatrix.swift                   # new: loader, chains, bytes, expectations
├── SceneMigrationMatrixTests.swift              # new: decode + repairReport cells
└── SceneMigrationMatrixMetaTests.swift          # new: completeness
Packages/ShowControl/Tests/ShowControlTests/ShowStoreMigrationMatrixTests.swift      # new
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveReader.swift                  # migrator parameter
Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveMigrationMatrixTests.swift # new
Packages/RenderGoldens/Tests/RenderGoldensTests/GoldenMigrationMatrixTests.swift     # new
Apps/projectM-iOS/Tests/SceneAutosaveMigrationMatrixTests.swift                      # new
docs/adr/0028-scene-document-format.md                                               # QA-004 amendment
```

**Structure Decision**: Each package carries a small copy of the matrix loader (Decodable structs
and the named test-only chains); SwiftPM cannot share test sources between packages without a new
library product, and a library holding test-only chains would ship them. The SceneFormat meta-test
checks that every runner file names its container.

## Complexity Tracking

None.
