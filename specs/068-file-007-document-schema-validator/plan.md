# Implementation Plan: FILE-007 Document Schema Validator

**Branch**: `feature/file-007` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/068-file-007-document-schema-validator/spec.md`

## Summary

One shared, bounded, structural JSON validator and a per-document schema, both in `LocalPortability`,
put in front of every JSON path that reached the platform decoder without bounds (spec baseline):

1. **LocalPortability**: `BoundedJSON.swift` — `JSONLimits`, `JSONShapeError` (17 typed reasons, each
   with a byte offset), `BoundedJSON.validate` (one forward pass over UTF-8 bytes with an explicit
   container stack, no recursion, no value tree, a bytes-examined counter); `DocumentSchema.swift` —
   name, oldest readable and current version, limits, a version verdict. `PortableArchive.read` gains a
   schema overload and validates `manifest.json` before any decoding; new error
   `PortableArchiveError.manifestRejected(JSONShapeError)` with three readable sentences.
2. **SceneArchive**: `SceneArchiveFormat.manifestSchema`; the reader passes it to `PortableArchive`.
3. **PresetLibrary**: `UserPresetArchiveFormat.manifestSchema`, `PresetCollectionsFile.schema`,
   `UserPresetsFile.schema`; the two local files validate before reading their version or migrating.
4. **Tests**: the hostile table, edge cases, a fixed-seed fuzz (LocalPortability); per-importer
   hostile manifests (SceneArchive, PresetLibrary); proof that SCN-001's reader and SHD-011's importer
   already refuse deep and oversize input before decoding (SceneFormat, Compositor tests only).
5. **Docs**: contract `contracts/bounded-json.md` (grammar, limits, errors, registry table); ADR-0029
   amended (manifests are shape-checked before decoding; duplicate keys refused). No new ADR number.

No app code changes, so no simulator run (roadmap verification: schema/fixture tests).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac; Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio)

**Primary Dependencies**: none new; the validator is plain Swift (no Foundation in its core loop;
`Data` only at the API edge)

**Storage**: unchanged

**Testing**: XCTest via `swift test` for LocalPortability, SceneArchive, PresetLibrary, SceneFormat and
Compositor on the Mac host and the Linux shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc
-DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape`)

**Target Platform**: iOS 26+ app; iOS 26+ / macOS 15 packages; Linux CI

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: linear in input bytes; a 4 MiB manifest validates in well under 100 ms on the
host (not asserted on wall clock; work is asserted by counter)

**Constraints**: memory beyond the input bounded by depth × small frame plus the keys of open objects
(only when duplicate keys are refused); unit tests about 1-2 s, suites under 1 minute (owner rule 7)

**Scale/Scope**: 4 documents adopt the validator; 2 keep equivalent own checks; ~600 lines of code and tests

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: plain Swift, no APIs beyond Foundation's `Data`. |
| VI. Modular boundaries | Pass: the validator lives in the dependency-free import package; each format declares its own schema in its own package; no new package-to-package edge. |
| IX. Pinned dependencies | Pass: none added. |
| X. Evidence-based quality | Pass: hostile table with exact errors, counter-based work bounds, fixed-seed fuzz, per-importer tests, Linux shape. |
| Security (imported files are untrusted) | Pass: this row closes unbounded decoding of untrusted manifests. |
| Privacy / no networking | Pass: no I/O; `check_compliance.py` covers the package. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/068-file-007-document-schema-validator/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/bounded-json.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/LocalPortability/Sources/LocalPortability/BoundedJSON.swift        (new)
Packages/LocalPortability/Sources/LocalPortability/DocumentSchema.swift     (new)
Packages/LocalPortability/Sources/LocalPortability/PortableArchive.swift    (manifest pre-check)
Packages/LocalPortability/Tests/LocalPortabilityTests/BoundedJSONTests.swift, BoundedJSONFuzzTests.swift (new)
Packages/SceneArchive/Sources/SceneArchive/SceneArchiveFormat.swift, SceneArchiveReader.swift
Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveManifestShapeTests.swift (new)
Packages/PresetLibrary/Sources/PresetLibrary/PresetCollectionsFile.swift, UserPresets/UserPresetsFile.swift, UserPresets/UserPresetArchive.swift
Packages/PresetLibrary/Tests/PresetLibraryTests/DocumentShapeTests.swift (new)
Packages/SceneFormat/Tests/SceneFormatTests/SceneHostileInputTests.swift (new, tests only)
Packages/Compositor/Tests/GeneratorGraphImportTests/GraphImportHostileInputTests.swift (new, tests only)
```

**Structure Decision**: validator in `LocalPortability` (research FILE-007-D1); no CI workflow or
project change, because no package is added.

## Complexity Tracking

None.
