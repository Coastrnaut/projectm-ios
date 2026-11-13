# Implementation Plan: SCN-013 Scene Migration

**Branch**: `feature/scn-013` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/081-scn-013-scene-migration/spec.md`

## Summary

Three layers:

1. **SceneFormat** (pure, Foundation-free, Linux): new `SceneMigration.swift` with
   `SceneMigrationStep` (from-version, identifier, summary, a pure transformation of the document
   object that records `SceneMigrationChange`s), `SceneMigrator` (ordered steps, target version,
   `migrate(_ root: SceneJSON) throws(SceneMigrationError) -> SceneMigrationResult`), the audit log
   (`SceneMigrationLogEntry`: step, from, to, change kind, path, detail) and `SceneMigrationRecord`
   on `SceneDecodeResult`. `SceneDocument.decode` runs `SceneMigrator.standard` (empty chain,
   target 1) between parsing and typed decoding; `decode(_:migrator:)` takes another chain for tests.
   `SceneDecodeError.migrationFailed(fromVersion:step:path:reason:)` is new; newer and invalid
   versions keep their existing refusals. `SceneRepairReport` adds a note entry in the new group
   `formatUpdated` ("Updated from an older format") for a migrated document.
2. **App and ShowStorage**: a shared rule "back up the original once before the first replacement".
   `SceneAutosaveStore` remembers the original bytes of a migrated main or backup file at load and
   writes `<name>.v<N>.backup` (O_CREAT|O_EXCL, F_FULLFSYNC) before the save that replaces or removes
   it; a backup failure refuses the save (new step `keepOriginal`). New events `migrated(from:to:steps:changes:)`
   and `keptOriginal(name)`. `ShowStore.saveScene` checks the stored file's version before replacing
   it (stateless: read, migrate-only decode) and writes the backup the same way; removing an
   unreferenced scene removes its backups.
3. **Golden legacy fixtures**: `Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/` with
   `manifest.json` (file, version, source, expected, covers) and `expected/` canonical documents;
   `SceneLegacyFixtureTests` decodes each input, compares the encoded result with the expected bytes
   and runs a leaf-by-leaf no-data-loss check against the audit log; synthetic chain tests prove the
   mechanism (`SceneMigrationTests`).

ADR-0028 is amended (migration chain, backup, audit log; no default overridden, so no new ADR).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals)

**Primary Dependencies**: SceneFormat (existing JSON value, parser, writer, decoder), ShowControl
(ShowStorage), the app's SceneAutosaveStore. No new package.

**Storage**: backups next to the stored files: `Application Support/Scenes/current.scene.v<N>.backup`,
`current.scene.bak.v<N>.backup`, `Application Support/Show/Scenes/<id>.scene.v<N>.backup`.

**Testing**: `swift test --package-path Packages/SceneFormat` on the host and the Linux shape
(`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`);
`swift test --package-path Packages/ShowControl`; app unit tests (`-only-testing:projectM-iOSTests`)
on an own iOS 27.2 simulator for the autosave backup. No UI test: no user-visible path changes
(the report note appears only inside the existing report).

**Target Platform**: iOS 26+ app; packages also macOS 15 and Linux.

**Performance Goals**: an empty chain costs one object lookup per decode; a migrated decode adds
one pass over the document. Package suite under 1 minute (owner rule 7).

**Constraints**: Constitution privacy (no scene content in diagnostics), no networking, nothing from
a document executed; SceneFormat keeps Foundation to `SceneValidation.swift` only.

**Scale/Scope**: chain of 0 production steps today; fixtures: 10 inputs.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: POSIX `open`, `fcntl(F_FULLFSYNC)`, `rename`; Foundation file APIs. |
| VI Modular boundaries | Pass: the mechanism is in SceneFormat; file handling stays with each store. |
| X Evidence-based quality | Pass: golden fixtures from real writers; synthetic steps labelled test-only; nothing claimed for a version that never existed. |
| Privacy (constraints section) | Pass: events carry versions, counts and fixed file names only (S4 test). |

## Project Structure

```text
Packages/SceneFormat/Sources/SceneFormat/SceneMigration.swift        (new)
Packages/SceneFormat/Sources/SceneFormat/SceneDecoding.swift         (decode runs the migrator)
Packages/SceneFormat/Sources/SceneFormat/SceneIssue.swift            (migrationFailed)
Packages/SceneFormat/Sources/SceneFormat/SceneRepair.swift           (formatUpdated note)
Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationTests.swift          (new)
Packages/SceneFormat/Tests/SceneFormatTests/SceneLegacyFixtureTests.swift      (new)
Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/…                  (new)
Packages/ShowControl/Sources/ShowStorage/ShowStore.swift             (backup before replace)
Packages/ShowControl/Tests/ShowControlTests/ShowStoreMigrationBackupTests.swift (new)
Apps/projectM-iOS/Coordinators/SceneAutosaveStore.swift              (backup, events)
Apps/projectM-iOS/Tests/SceneAutosaveMigrationTests.swift            (new)
docs/adr/0028-scene-document-format.md                               (amendment)
```

## Complexity Tracking

None.
