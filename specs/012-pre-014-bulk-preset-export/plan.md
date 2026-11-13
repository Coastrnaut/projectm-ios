# Implementation Plan: PRE-014 Bulk preset export

**Branch**: `feature/pre-014` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/012-pre-014-bulk-preset-export/spec.md`

## Summary

My Presets gets an Export sheet: the user picks exportable presets (all selected), the app writes
one stored (uncompressed) ZIP archive with `manifest.json` and the preset texts into a private
temporary folder, shows a summary of what was exported and what was left out, and opens the
system share sheet; the temporary file is deleted when the share sheet closes. A new
Foundation-only package, `LocalPortability` (the roadmap's proposed name), holds the reusable
container: CRC-32, SHA-256 (moved from `PresetLibrary.ContentHash`, which now delegates), a
bounded stored-ZIP writer and reader, archive path rules, and a generic "manifest with checksummed
file list" layer that FILE-001/FILE-002 and PRE-013 can reuse. `PresetLibrary` adds the preset
manifest (format `org.projectmios.user-presets`, version 1), the export plan (what is exportable
and why not, ADR-0008), the writer and the validating reader. The app layer is thin: one
coordinator section, one new view file and a toolbar button.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2 / iOS SDK 27.2 (ADR-0002)

**Primary Dependencies**: none new. Foundation; SwiftUI; UIKit `UIActivityViewController` (the
system share sheet, public API) through a `UIViewControllerRepresentable`.

**Storage**: no change to `<Application Support>/UserPresets/` (record version 2 stays). Export
writes only under `<tmp>/PresetExport/<uuid>/`, deleted after sharing and at launch.

**Testing**: XCTest. `LocalPortability` and `PresetLibrary` with `swift test` on the macOS host
(and Linux in CI); app unit tests and UI tests on the iOS 27.2 simulator "iPhone 18 Pro".

**Target Platform**: iOS and iPadOS 26.0+; the packages also build for macOS 15 and Linux.

**Project Type**: mobile app with SwiftPM packages under `Packages/`

**Performance Goals**: 1,000 small presets exported in under 10 s on the simulator (S6,
indicative). Memory: one preset text at a time plus the manifest while writing.

**Constraints**: public APIs only; no networking (FR-068); no new entitlement or dependency;
deterministic output; no logging of names or ids (R20).

**Scale/Scope**: PRE-012 limits: 1,000 presets of at most 512 KiB, 4 MiB manifest.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I. Public APIs only | Pass | Foundation file APIs, `UIActivityViewController`, SwiftUI. Own ZIP code instead of any private or third-party archiver. |
| II-V. Capture | n/a | No capture code. |
| VI. Modular boundaries | Pass | Container code in `LocalPortability` (no preset knowledge); preset format, export rules and reader in `PresetLibrary`; the app only presents. |
| VII. Real-time audio safety | Pass | No audio code. |
| VIII. Upstream fidelity | Pass | No engine change. |
| IX. Pinned dependencies, license review | Pass | No new dependency. Copies of locked-pack presets never leave (ADR-0008); exported copies carry `duplicateOf`, `rightsVerified = false` and the pack's statement verbatim; imported presets carry their license lines and the "not verified" flag. |
| X. Evidence | Pass | Tests first with a recorded red run; golden archive hash; tamper tests; simulator app and UI tests; device sharing left to the final device phase. |
| Privacy | Pass | Export is user-initiated; the file leaves only through the user's share action; no device or purchase data in the manifest; temporary files deleted. Privacy policy gets one sentence. |

Post-design re-check: unchanged (Pass). New package justified in research D1.

## Project Structure

### Documentation (this feature)

```text
specs/012-pre-014-bulk-preset-export/
├── spec.md
├── plan.md            # this file
├── research.md        # D1-D8
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── preset-archive.md
│   └── preset-archive-manifest-v1.schema.json
├── checklists/requirements.md
└── tasks.md           # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/LocalPortability/                        # NEW package, Foundation only
├── Package.swift
├── Sources/LocalPortability/
│   ├── CRC32.swift                # IEEE CRC-32
│   ├── PortableSHA256.swift       # moved from PresetLibrary.ContentHash
│   ├── ArchivePath.swift          # safe relative path rules
│   ├── StoredZip.swift            # stored-only ZIP writer (streaming) and bounded reader
│   └── PortableArchive.swift      # manifest.json + checksummed file list, limits, errors
└── Tests/LocalPortabilityTests/
    ├── CRC32Tests.swift, PortableSHA256Tests.swift
    ├── ArchivePathTests.swift
    ├── StoredZipTests.swift       # round trip, determinism, tamper, bounds
    ├── PortableArchiveTests.swift
    └── NoNetworkingTests.swift    # source scan of the export path
Packages/PresetLibrary/
├── Package.swift                  # + dependency on ../LocalPortability
├── Sources/PresetLibrary/UserPresets/
│   ├── ContentHash.swift          # sha256 delegates to PortableSHA256
│   ├── UserPresetArchive.swift    # NEW: manifest types, writer, validating reader, errors
│   ├── UserPresetExport.swift     # NEW: export plan, exclusion reasons, summary words
│   └── UserPresetLibrary.swift    # + exportPlan(), export(ids:to:…)
└── Tests/PresetLibraryTests/
    ├── UserPresetArchiveTests.swift   # NEW: round trip, golden hash, tamper, ADR-0008
    └── UserPresetExportTests.swift    # NEW: classification, summary, rollback
Apps/projectM-iOS/
├── Coordinators/UserPresetsCoordinator.swift  # export state, temp folder, cleanup, test hook
├── Views/UserPresetExportView.swift           # NEW: selection sheet, summary, share sheet
├── Views/UserPresetsView.swift                # Export toolbar button and sheet
├── Tests/UserPresetExportAppTests.swift       # NEW
└── UITests/UserPresetExportUITests.swift      # NEW
project.yml                        # + LocalPortability package entry (comment-level change)
.github/workflows/ios-ci.yml       # + LocalPortability in every package loop
docs/privacy-policy.md             # one sentence in the PRE-012 paragraph
docs/test-reports/preset-export.md # NEW evidence report
```

**Structure Decision**: one new Foundation-only package for the container (R16; the roadmap's
`LocalPortability`), preset rules in `PresetLibrary`, thin app layer.

## Design

### Layers

1. **`LocalPortability.StoredZipWriter`**: appends entries through a sink closure
   (`(Data) throws -> Void`, a `FileHandle` in the app, a buffer in tests), computing CRC-32 as
   it goes; `finish()` writes the central directory and end record. No ZIP64; the limits keep
   every offset below 4 GiB.
2. **`LocalPortability.StoredZipReader`**: parses `Data` (memory-mapped in the app), end record
   first, every count and offset checked against the data size and the limits before use; local
   and central headers must agree; CRC-32 verified.
3. **`LocalPortability.PortableArchive`**: `Writer` adds files (SHA-256 recorded) and finishes
   with a caller-built `manifest.json` that embeds the file list; `read` checks the format name,
   version (newer → its own error), every listed file's length and SHA-256, and that no entry is
   unlisted. Returns the manifest bytes for the caller's own section.
4. **`PresetLibrary.UserPresetExportPlan`**: classifies the store's records (ADR-0008 rules).
5. **`PresetLibrary.UserPresetArchive`**: builds the preset manifest; writer verifies each stored
   text against its record before writing; reader decodes and validates every preset (reusing
   `UserPreset.isWellFormed`, the git blob hash, the ADR-0008 origin rule).
6. **`UserPresetLibrary.export(ids:appVersion:exportedAt:to:)`**: actor method; writes the
   archive to the given file; any failure deletes the file and returns an error.
7. **App**: `UserPresetsCoordinator.prepareExport()`, `export(ids:)`, `finishSharing()`; the view
   presents the share sheet from a representable and calls `finishSharing` in the completion.

### Transactions and rollback

- Export never writes inside the user-preset store; the store is only read.
- The archive is written to `<tmp>/PresetExport/<uuid>/<name>.zip`. Any error (stored text does
  not match its record, write fails) closes and deletes the folder; nothing is shared.
- After the share sheet closes (any outcome) the folder is deleted. At `load()` the whole
  `<tmp>/PresetExport` folder is deleted (a launch that ended during sharing).

### Deterministic tests

- Fixed export date, app version and ids → golden SHA-256 of the archive bytes.
- Fixture store built through `UserPresetLibrary` with an injected clock and id maker and a
  scripted trial (PRE-012 `FakeTrial`).
- Tamper cases build archives with the real writer, then patch bytes at computed offsets.
- Interoperability checked once with `unzip -t` and Python's `zipfile` (evidence, not CI).
- UI test: `-uitestExportPresetTo <host path>` (DEBUG only) copies the produced archive for the
  test to read; the test stops at the share sheet.

## Complexity Tracking

| Choice | Why needed | Simpler alternative rejected because |
|---|---|---|
| New package `LocalPortability` | R16: FILE-001/FILE-002/PRE-013 must reuse the container without depending on presets | Putting it in `PresetLibrary` would force scene archives to depend on the preset library |
| Own stored-ZIP code | No public ZIP writer in Foundation on iOS; no third-party dependencies | Apple Archive is not readable on Linux or by common tools (research D2) |
