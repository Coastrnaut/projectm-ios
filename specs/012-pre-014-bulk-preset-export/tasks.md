# Tasks: PRE-014 Bulk preset export

**Input**: `specs/012-pre-014-bulk-preset-export/` (spec, plan, research, data-model, contracts,
quickstart)

**Conventions**: task IDs are `PRE-014-T01…`. Tests come first within each phase and their
failing ("red") run is recorded before the code is written. Tags: `{mac}` runs on the Mac host
(`swift test`), `{sim}` needs the iOS 27.2 simulator "iPhone 18 Pro", `{device}` needs a physical
device and belongs to the roadmap's final device stage (not run here). A task is ticked only when
its evidence was produced, with " — Verified <date>: <how>". `[P]` = can run in parallel with
the neighbouring tasks (different files).

Paths: `LP` = `Packages/LocalPortability`, `UP` =
`Packages/PresetLibrary/Sources/PresetLibrary/UserPresets`, `PKGT` =
`Packages/PresetLibrary/Tests/PresetLibraryTests`, `APP` = `Apps/projectM-iOS`.

## Phase 1: Setup

- [X] PRE-014-T01 {mac} Create the package `LP` (`LP/Package.swift`, swift-tools 6.0, platforms
  iOS 26 / macOS 15, library `LocalPortability`, test target `LocalPortabilityTests`, no
  dependencies; Foundation only) and add `.package(path: "../LocalPortability")` to
  `Packages/PresetLibrary/Package.swift`. Evidence: `swift build` of both packages. — Verified 2026-11-12: `swift build` of LocalPortability and PresetLibrary (with the new dependency) succeeded; PresetLibrary 166 tests still pass.
- [ ] PRE-014-T02 [P] {mac} Wire the package: `project.yml` `packages:` entry, and
  `LocalPortability` in every package loop of `.github/workflows/ios-ci.yml` (Linux, macOS host,
  generic iOS compile, both simulator loops). Evidence: `xcodegen generate` succeeds; diff review.

## Phase 2: Foundational (container, checksums, paths; blocks every story)

- [X] PRE-014-T03 [P] {mac} Write `LP/Tests/LocalPortabilityTests/CRC32Tests.swift` (IEEE vector
  "123456789" → `0xCBF43926`, empty → 0, incremental equals one-shot) and
  `PortableSHA256Tests.swift` (FIPS 180 vectors "", "abc", the 448-bit message, 1,000,000 × "a").
  Record the red run. — Verified 2026-11-12: red run: `swift build --build-tests` failed (target `LocalPortability` empty, `CRC32`/`PortableSHA256` undefined); 8 tests now.
- [X] PRE-014-T04 {mac} Implement `LP/Sources/LocalPortability/CRC32.swift` and
  `PortableSHA256.swift` (the SHA-256 code moved from `UP/ContentHash.swift`); make
  `ContentHash.sha256Hex` delegate (signature unchanged). Evidence: T03 passes;
  `ContentHashTests` still pass. — Verified 2026-11-12: CRC32Tests 5 and PortableSHA256Tests 3 pass; `ContentHashTests` pass inside the PresetLibrary run (166 tests, 0 failures).
- [X] PRE-014-T05 [P] {mac} Write `LP/Tests/LocalPortabilityTests/ArchivePathTests.swift`
  (research D5): accepted `presets/a.milk`, `manifest.json`, non-Latin names; refused "",
  `/x`, `../x`, `a/../x`, `./x`, `a//b`, `a\b`, `C:x`, control characters, 256-byte path,
  9 components, trailing `/`; collision key equal for `A.milk`/`a.milk` and NFC/NFD forms.
  Record the red run. — Verified 2026-11-12: red run recorded with T07/T09: `swift build --build-tests` 62 errors (`ArchivePath`, `StoredZipWriter`, `PortableArchive` not found).
- [X] PRE-014-T06 {mac} Implement `LP/Sources/LocalPortability/ArchivePath.swift`. Evidence: T05
  passes. — Verified 2026-11-12: ArchivePathTests 4 tests pass.
- [X] PRE-014-T07 {mac} Write `LP/Tests/LocalPortabilityTests/StoredZipTests.swift`: round trip
  of 3 entries (bytes and names identical); identical input → identical bytes; writer refuses an
  unsafe or duplicate path; reader refuses: empty data, random
  bytes (`notAZip`), every truncation of a small archive (`truncated` or `malformed`, never a
  crash), a flipped data byte (`checksumMismatch`), a compressed method, the encryption flag,
  an archive comment, ZIP64 sentinels, a local/central name mismatch, overlapping entries, more
  entries than `maxEntries`, an entry over `maxEntryBytes` (refused before its bytes are read),
  `../x` and absolute names, case-insensitive duplicates. Record the red run. — Verified 2026-11-12: red run: the same 62-error build; 24 StoredZipTests.
- [X] PRE-014-T08 {mac} Implement `LP/Sources/LocalPortability/StoredZip.swift`
  (`StoredZipWriter`, `StoredZipReader`, `StoredZipLimits`, `StoredZipError` with the contract's
  messages). Evidence: T07 passes. — Verified 2026-11-12: StoredZipTests 24 pass (`swift test --package-path Packages/LocalPortability`).
- [X] PRE-014-T09 {mac} Write `LP/Tests/LocalPortabilityTests/PortableArchiveTests.swift`: a
  manifest with `format`, `formatVersion`, `files` round-trips; refused: missing manifest,
  manifest over its limit, malformed JSON, wrong format, newer version (`newerVersion(2)`),
  unlisted entry, listed-but-missing file, length and SHA-256 mismatches, duplicate listed path;
  and `NoNetworkingTests.swift` scanning the sources of `LP` and the export files of `UP` for
  networking API names (tokens built by concatenation so the compliance script does not flag the
  test). Record the red run. — Verified 2026-11-12: red run: the same build; PortableArchiveTests 14 and NoNetworkingTests 1 (failed until the PresetLibrary export files existed).
- [X] PRE-014-T10 {mac} Implement `LP/Sources/LocalPortability/PortableArchive.swift`
  (`PortableFileRecord`, `PortableArchiveLimits`, `PortableArchiveWriter`, `PortableArchive.read`,
  `PortableArchiveContents`, `PortableArchiveError`). Evidence: T09 passes; `swift test
  --package-path Packages/LocalPortability` all pass. — Verified 2026-11-12: `swift test --package-path Packages/LocalPortability`: 51 tests, 0 failures.

**Checkpoint**: container ready; commit.

## Phase 3: User Story 2 - Round trip without network (P1, the acceptance)

Goal: an archive of user presets reads back with identical ids, metadata and texts.
Independent test: `swift test --package-path Packages/PresetLibrary --filter UserPresetArchiveTests`.

- [X] PRE-014-T11 [US2] {mac} Write `PKGT/UserPresetArchiveTests.swift`: build a fixture library
  through `UserPresetLibrary` (injected clock, id maker, `FakeTrial`): an imported preset with
  license lines and an author from the file name, an imported preset with warnings and emoji in
  its name, an edited copy of an Included preset (`duplicateOf`, `modifiedAt`, `rightsVerified`
  false, pack statement); export all; read back with `UserPresetArchiveReader`; assert ids,
  names, authors, `authorFromFileName`, original file names, origins, `duplicateOf`,
  `rightsVerified`, license lines, warnings, `importedAt`, `modifiedAt`, hashes, sizes and texts
  equal the stored records (S1); `ExportedUserPreset.userPreset()` passes `isWellFormed`; the
  manifest validates against the contract's rules ("`path` = `presets/<uuid>.milk`", "`format`
  exactly `org.projectmios.user-presets`", "`formatVersion` 1"); a fixed date and ids give the
  golden SHA-256 twice (S4); tamper cases (S3): flipped text byte, manifest `path` `../x` and
  `/x`, a text that differs from `blobHash`, duplicate ids, `rightsVerified` true, a
  `duplicateOf` with `requiresLibraryUnlock` true or `packID` not `included`, 1,001 presets,
  formatVersion 2 → `newerVersion`, truncated archive. Record the red run. — Verified 2026-11-12: red run: with UserPresetArchive.swift, UserPresetExport.swift and the library methods set aside, `swift build --build-tests` failed (10 errors: no `exportPlan`, `export`, archive types); 19 tests in UserPresetArchiveTests.
- [X] PRE-014-T12 [US2] {mac} Implement `UP/UserPresetArchive.swift`
  (`UserPresetArchiveFormat`, `ExportedUserPreset`, `UserPresetArchiveManifest`,
  `UserPresetArchive`, `UserPresetArchiveWriter`, `UserPresetArchiveReader`,
  `UserPresetArchiveError` with the contract's words). Evidence: T11 passes. — Verified 2026-11-12: UserPresetArchiveTests 19 pass (1 skipped by design: the interoperability writer without EXPORT_FIXTURE_OUT); golden SHA-256 ad40f883…3794; the golden manifest matches the schema's keys, required fields, patterns and constants (Python key check; no jsonschema module on this Mac).
- [ ] PRE-014-T13 [US2] {mac} Interoperability: write the golden archive to a file and check it
  with `unzip -t` and Python's `zipfile` (`testzip()` is `None`, names as expected). Evidence:
  the command output in `docs/test-reports/preset-export.md`.

## Phase 4: User Story 3 - Paid and unsafe content never leaves (P1)

Goal: ADR-0008 and the safety exclusions in the export plan and the export itself.
Independent test: `swift test --package-path Packages/PresetLibrary --filter UserPresetExportTests`.

- [X] PRE-014-T14 [US3] {mac} Write `PKGT/UserPresetExportTests.swift`: a library with an
  imported playable preset, an Included copy, a locked-pack copy with the library unlocked and
  then edited, the same while locked, a quarantined file and a waiting preset: `exportPlan()`
  lists exactly the first two and counts `fullLibraryCopy` 2, `quarantined` 1, `notChecked` 1;
  `export(ids:)` given every id writes exactly two presets (S2); the summary message names each
  group; a stored text changed on disk → `contentMismatch`, the output file is deleted; a write
  failure (sink throws) → `writeFailed`, file deleted; an id removed meanwhile is counted
  `unavailable`; 1,000 small presets export in under 10 s (S6); no ids → `nothingSelected`; a newer-format
  record → `libraryUnavailable`; the store directory is byte-identical before and after (export
  only reads). Record the red run. — Verified 2026-11-12: red run: the same build as T11; 9 tests in UserPresetExportTests.
- [X] PRE-014-T15 [US3] {mac} Implement `UP/UserPresetExport.swift` (`UserPresetExportPlan`,
  `UserPresetExportExclusion`, `UserPresetExportSummary`, `UserPresetExportError`) and
  `UserPresetLibrary.exportPlan()` / `export(ids:appVersion:exportedAt:to:)` in
  `UP/UserPresetLibrary.swift`. Evidence: T14 and T11 pass; full `PresetLibrary` suite passes. — Verified 2026-11-12: UserPresetExportTests 9 and UserPresetArchiveTests 19 pass; full PresetLibrary suite 194 tests, 2 skipped, 0 failures.

**Checkpoint**: library complete; commit.

## Phase 5: User Story 1 - Export from My Presets (P1)

Goal: select, export, summary, share sheet, cleanup.
Independent test: app unit tests and `UserPresetExportUITests` on the simulator.

- [ ] PRE-014-T16 [US1] {sim} Write `APP/Tests/UserPresetExportAppTests.swift`: the coordinator
  with a temporary library: `prepareExport()` lists the exportable presets all selected with the
  exclusion words; `export(ids:)` writes a file under `<tmp>/PresetExport/` that
  `UserPresetArchiveReader` reads with the selected presets only; `finishSharing()` deletes it
  (S5); `load()` deletes leftovers; Export is unavailable while importing and for a newer record;
  the summary is announced. Record the red run.
- [ ] PRE-014-T17 [US1] {sim} Implement the export section of
  `APP/Coordinators/UserPresetsCoordinator.swift` (state, temporary folder, cleanup, DEBUG hook
  `-uitestExportPresetTo`, app version from the bundle). Evidence: T16 passes.
- [ ] PRE-014-T18 [US1] {sim} Implement `APP/Views/UserPresetExportView.swift` (selection sheet,
  Select All / None, count, exclusions footer, Export, summary, share sheet representable with
  completion → `finishSharing`) and the "Export…" toolbar button in `APP/Views/UserPresetsView.swift`;
  accessibility identifiers and labels per the contract; Dynamic Type safe (labels wrap).
- [ ] PRE-014-T19 [US1] {sim} Write `APP/UITests/UserPresetExportUITests.swift`: import a preset
  (`-uitestImportPreset`), open My Presets → Export…, the row is selected, Select None disables
  Export, Select All enables it, Export → the summary says "Exported 1 preset" and the share sheet
  appears; the archive copied by `-uitestExportPresetTo` starts with `PK\u{3}\u{4}` and contains
  `manifest.json` and the preset name; a second launch at the accessibility text size
  (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`) still shows a
  hittable Export button and row (R17). Evidence: the test passes; red run recorded before T18.

## Phase 6: User Story 4 - Hostile archives refused (P2)

- [ ] PRE-014-T20 [US4] {mac} Confirm coverage: every refusal in contract §3-4 has a test in T07,
  T09 or T11 (table in `docs/test-reports/preset-export.md`); add any missing test. Evidence:
  the table with test names.

## Phase 7: Polish

- [ ] PRE-014-T21 [P] {mac} `docs/privacy-policy.md`: one sentence in the PRE-012 paragraph
  (export leaves only through the user's share action; no purchase data). Evidence: diff.
- [ ] PRE-014-T22 {mac} `docs/test-reports/preset-export.md`: commands, counts, golden hash,
  interoperability output, the refusal table, what is not verified.
- [ ] PRE-014-T23 {mac} Gates: `python3 scripts/check_compliance.py`, `python3
  scripts/validate_docs.py`, `python3 scripts/test_scripts.py`; `swift test` for `LP` and
  `PresetLibrary` twice; `grep` shows no `print`, `Logger` or `os_log` call in the export files
  (R20). Evidence: outputs in the report.
- [ ] PRE-014-T24 {sim} App unit tests, `UserPresetsUITests`, `UserPresetEditingUITests`,
  `UserPresetExportUITests` on the simulator, twice. Evidence: `Executed N tests` lines in the
  report (known environmental failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0`).
- [ ] PRE-014-T25 {device} Final device phase: on D1 export three presets (two imports, an
  Included copy) with a pack copy present, Save to Files, open the ZIP in Files, check the pack
  copy is absent; repeat on D3 (iPadOS 26.5, popover share sheet). Not run here (ADR-0008
  decision 7).

## Dependencies

- T01 → T02; T03-T10 (container) → everything else.
- US2 (T11-T13) → US3 (T14-T15) → US1 (T16-T19) → US4 review (T20) → Polish.
- US3's export uses US2's writer; the app uses both.

## Parallel examples

- T03 and T05 (different test files); T21 with any phase.

## Implementation strategy

MVP = Phases 1-4 (the acceptance round trip and ADR-0008 in the library), then the UI (US1).
Each phase ends with a commit `PRE-014 T..-T..: …`.
