# Tasks: FILE-007 Document Schema Validator

**Input**: `specs/068-file-007-document-schema-validator/` (spec, plan, research, data-model, contract,
quickstart)

Budgets (owner rule 7): each unit test about 1-2 s (≤ 10 s), each package suite < 1 minute. No app
code changes, so no simulator task; no device task.

## Phase 1: Foundational — LocalPortability (blocks every story)

- [X] FILE-007-T01 `JSONLimits`, `JSONShapeError` (17 reasons with offsets and a family), `JSONShapeSummary` and `BoundedJSON.validate` (one pass, explicit stack, strict UTF-8, escapes, numbers, duplicate keys on decoded keys, bytes-examined counter) in `Packages/LocalPortability/Sources/LocalPortability/BoundedJSON.swift` (FILE-007-R1-R4; contract C1) — Verified 2026-11-13: `swift test --package-path Packages/LocalPortability` (72 tests pass, host and Linux shape); BoundedJSONTests (9)
- [X] FILE-007-T02 `DocumentSchema` (name, oldest readable and current version, limits, `verdict(for:)`, `validate(_:)`) in `Packages/LocalPortability/Sources/LocalPortability/DocumentSchema.swift` (FILE-007-R5; contract C2) — Verified 2026-11-13: BoundedJSONTests.testDocumentSchemaVerdictsAndCap

## Phase 2: US2 — one validator with exact, typed refusals (P1)

**Independent test**: the hostile table with exact errors and work bounds.

- [X] FILE-007-T03 [P] [US2] `Packages/LocalPortability/Tests/LocalPortabilityTests/BoundedJSONTests.swift`: hostile table (100,000-deep arrays, deep objects, 10 MB string, 1,000,000-element array, invalid UTF-8 kinds, overlong number, duplicate keys incl. escaped, BOM, trailing garbage, unterminated string) and edge cases (brackets in strings, invalid numbers, control characters, bad escapes, lone surrogates, scalar root, empty, exact-limit accept / one-over refuse), each with exact error, offset and `bytesExamined ≤ offset + 1` (FILE-007-S1) — Verified 2026-11-13: BoundedJSONTests.testHostileTable (18 cases incl. 100,000-deep arrays → nestingTooDeep at 8, 10 MB string → tooLarge with 0 bytes examined, 1,000,000 elements → tooManyElements at 131,073), testGrammarEdgeCases (26), testAcceptedShapes, testLimitsAreInclusive; every refusal examined ≤ offset + 1 bytes (BOM: 3); suite 0.27 s
- [X] FILE-007-T04 [P] [US2] `Packages/LocalPortability/Tests/LocalPortabilityTests/BoundedJSONFuzzTests.swift`: fixed-seed fuzz (≥ 2,000 mutations of valid documents) returns only success or a typed error; every accepted input also decodes with `JSONSerialization` (FILE-007-S3) — Verified 2026-11-13: BoundedJSONFuzzTests.testFixedSeedFuzzReturnsOnlyTypedResults (2,500 mutations, seed 0x0F11E007, 0.02 s; accepted inputs all parse with JSONSerialization)

## Phase 3: US1 — hostile archive manifests refused before decoding (P1)

**Independent test**: archives with hostile manifests (valid ZIP checksums) through both readers.

- [X] FILE-007-T05 [US1] `PortableArchive.read(_:schema:limits:)` validating `manifest.json` before any decoding; `PortableArchiveError.manifestRejected(JSONShapeError)` with the three sentences; existing overload builds a default schema; tests in `PortableArchiveTests.swift` (FILE-007-R6; contract C3) — Verified 2026-11-13: PortableArchiveTests.testHostileManifestsAreRejectedBeforeDecoding, testManifestOverTheSchemaByteLimitIsRejected, testRejectionMessagesFollowTheFamily, testNewerVersionIsStillRecognisedAfterTheShapeCheck; testRefusesMalformedManifests now expects manifestRejected
- [X] FILE-007-T06 [US1] `SceneArchiveFormat.manifestSchema` used by `SceneArchiveReader`; `Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveManifestShapeTests.swift`: deep, duplicate `files` key, oversize string, too many elements → `.archive(.manifestRejected(...))`; a valid archive still reads (FILE-007-S2, R9) — Verified 2026-11-13: SceneArchiveManifestShapeTests (4); SceneArchive 25 tests pass, host and Linux shape
- [X] FILE-007-T07 [US1] `UserPresetArchiveFormat.manifestSchema` used by `UserPresetArchiveReader`; preset-archive cases in `Packages/PresetLibrary/Tests/PresetLibraryTests/DocumentShapeTests.swift` (FILE-007-S2, R9) — Verified 2026-11-13: DocumentShapeTests.testHostilePresetArchiveManifestsAreRefusedBeforeDecoding, testSchemasAreDeclaredWithTheirFormats; UserPresetArchiveTests unchanged and passing

## Phase 4: US3 — local library files bounded too (P2)

- [X] FILE-007-T08 [US3] `PresetCollectionsFile.schema`, `UserPresetsFile.schema`; both `decode` functions validate before reading the version or migrating (refusal → `unreadable`); tests in `DocumentShapeTests.swift`: deep, duplicate key, BOM → unreadable; golden files still decode (FILE-007-R7, R9) — Verified 2026-11-13: DocumentShapeTests (collections, user presets, migration output, newer still newer); golden collections-v1, user-presets-v1/v2 decode; PresetLibrary 207 tests pass (2 skipped as before), host and Linux shape. Local schemas accept any top-level value: the PRE-007 version-0 fixture is an array

## Phase 5: Existing equivalent bounds proven (FILE-007-R8)

- [X] FILE-007-T09 [P] `Packages/SceneFormat/Tests/SceneFormatTests/SceneHostileInputTests.swift` and `Packages/Compositor/Tests/GeneratorGraphImportTests/GraphImportHostileInputTests.swift`: 100,000-deep and over-size inputs refused with `nestingTooDeep` / `tooLarge` before decoding (FILE-007-S2) — Verified 2026-11-13: SceneHostileInputTests (3) and GraphImportHostileInputTests (2) pass, host and Linux shape

## Phase 6: Polish

- [X] FILE-007-T10 ADR-0029 amendment (manifests shape-checked before decoding, duplicate keys refused, schema per document); spec status; `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py` — Verified 2026-11-13: ADR-0029 amended (FILE-007 section); `python3 scripts/check_compliance.py` OK, `python3 scripts/validate_docs.py` OK (623 files)
- [X] FILE-007-T11 Full suites of LocalPortability, SceneArchive, PresetLibrary, SceneFormat and Compositor on the Mac host and the Linux shape (FILE-007-S4, R10) — Verified 2026-11-13: host: LocalPortability 72 (3.0 s), SceneArchive 25 (0.1 s), PresetLibrary 207 with 2 skipped (24-35 s), SceneFormat 40 (0.8 s), Compositor 391 with 1 skipped (9.9 s); Linux shape: 72, 25, 207, 40, 258; zero failures

## Dependencies

T01 → T02 → (T03, T04, T05); T05 → T06, T07; T02 → T08; T09 independent; T10, T11 last.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: R1-R4 → T01, T03; R5 → T02, T06-T08; R6 → T05-T07; R7 → T08; R8 → T09; R9 → T06-T08, T11;
R10 → T11. S1 → T03; S2 → T06-T09; S3 → T04; S4 → T11. No requirement without a task, no task without a
requirement. Fixed: US2 scenario 1 needed "any top-level value allowed" (an array root is otherwise
`notAnObject`); contract C1 now states when the root check runs. No constitution conflict.
