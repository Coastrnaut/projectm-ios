# Tasks: SCN-001 Versioned Scene Format

**Input**: Design documents from `specs/059-scn-001-versioned-scene-format/` (spec, plan, research,
data-model, contracts/scene-document.md, quickstart)

**Tests**: requested by the spec (S1-S5) and owner rule 7 budgets (unit ≈ 1-2 s, suite < 1 min).
Tick a task `[X]` only when verified, with " — Verified <date>: <how>". No task needs a device or
the simulator (no app change).

Format: `- [ ] SCN-001-Tnn [P?] [Story?] Description with file path`

## Phase 1: Setup

- [X] SCN-001-T01 Create `Packages/SceneFormat/Package.swift` (tools 6.0, iOS 26 / macOS 15; dependencies `../ParameterGraph`, `../Compositor`, `../VisualGenerators`; library target `SceneFormat` depending on the `ParameterGraph` and `Compositor` products; test target `SceneFormatTests` depending on `SceneFormat`, `ParameterGraph`, `Compositor`, `VisualGenerators`) with a header comment citing SCN-001 and ADR, and add `SceneFormat` to the 5 package loops in `.github/workflows/ios-ci.yml` — Verified 2026-11-13: `swift build` and `xcodebuild -scheme SceneFormat -destination generic/platform=iOS build` succeed; `grep -c "Compositor SceneFormat; do" .github/workflows/ios-ci.yml` = 5

## Phase 2: Foundational (blocks all stories)

- [X] SCN-001-T02 [P] `SceneJSON` (null, bool, number, string, array, object) and `SceneNumber` (exact written text; `init(_ d: Double)` from `description`, `init(_ i: Int64)`, `doubleValue` finite-only, `int64Value`) in `Packages/SceneFormat/Sources/SceneFormat/SceneJSON.swift` — Verified 2026-11-13: SceneJSONTests.testNumbersKeepTheirWrittenText (host and Linux shape)
- [X] SCN-001-T03 [P] Bounded parser in `Packages/SceneFormat/Sources/SceneFormat/SceneJSONParser.swift`: UTF-8 validation, RFC 8259 grammar, number lexeme kept, `\u` escapes with surrogate pairs, depth ≤ 32 (`nestingTooDeep`), duplicate keys refused with their path (`duplicateKey`), errors with byte offset (`notJSON`) — Verified 2026-11-13: SceneJSONTests 7/7 (malformed table with offsets, invalid UTF-8, depth 32 and a 100,000-deep input, duplicate keys with paths), host and Linux shape
- [X] SCN-001-T04 [P] Canonical writer in `Packages/SceneFormat/Sources/SceneFormat/SceneJSONWriter.swift`: no white space, keys sorted by UTF-8 bytes, minimal escaping (contract C2) — Verified 2026-11-13: SceneJSONTests.testCanonicalFormSortsKeysAndRemovesWhiteSpace, testStringsRoundTripWithMinimalEscaping
- [X] SCN-001-T05 Model types, constants and limits (`formatName`, `currentVersion`, 1 MiB, depth 32, 8 layers, 32 bindings, 1,024 parameter values, 16 assets, 64 values per layer, 64 generators, 256 connections, name 1…120 characters, instance 1…9007199254740991) in `Packages/SceneFormat/Sources/SceneFormat/SceneDocument.swift`, `SceneIssue` and its codes in `SceneIssue.swift`, `SceneDecodeError` with the contract C4 messages — Verified 2026-11-13: SceneDecodeErrorTests (every C4 message), SceneValidationTests (every C5 code)
- [X] SCN-001-T06 Typed decoding (format, version, limits before typed decoding, defaults, clamping and dropped-field warnings) in `Packages/SceneFormat/Sources/SceneFormat/SceneDecoding.swift` and encoding in `SceneEncoding.swift`; `SceneDocument.decode(_:)` and `encoded()` — Verified 2026-11-13: SceneRoundTripTests 5/5, SceneDecodeErrorTests.testDecodeWarningsForClampedAndDroppedFields
- [X] SCN-001-T07 [P] JSON layer tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneJSONTests.swift`: escapes, unicode, numbers (`0.1`, `1e-07`, `-0.0`, `9007199254740993` kept as text), depth, duplicates, invalid UTF-8, canonical output — Verified 2026-11-13: SceneJSONTests 7/7, host and Linux shape

## Phase 3: User Story 1 — A scene survives a save and reopen unchanged (P1, MVP)

**Goal**: decode → encode → decode is semantically equal and byte-identical. **Independent test**: the all-kinds fixture and the property test.

- [X] SCN-001-T08 [US1] All-kinds fixture builder (camera, both spectra, photo, video, text, material, generator graph, unknown kind; composite settings and transforms; parameters of every value kind; bindings with mapping, envelope, mix and an expression; a modulation generator and connection; assets of every type) in `Packages/SceneFormat/Tests/SceneFormatTests/SceneFixtures.swift` — Verified 2026-11-13: SceneRoundTripTests.testTheFixtureIsValidApartFromItsUnknownKind (only issue: unknownLayerKind)
- [X] SCN-001-T09 [US1] Round-trip acceptance tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneRoundTripTests.swift`: fixture → encode → decode → equal; canonical bytes identical after a second encode; reordered keys with white space decode equal (S1) — Verified 2026-11-13: SceneRoundTripTests 5/5 (equal documents, identical canonical bytes, key order and white space ignored, bit-exact equality)
- [X] SCN-001-T10 [US1] Seeded property test (SplitMix64, 500 random valid scenes including unknown kinds, extreme doubles and unicode strings) in `Packages/SceneFormat/Tests/SceneFormatTests/ScenePropertyTests.swift` (S1) — Verified 2026-11-13: ScenePropertyTests: 500 seeded scenes, 0 failures, 0.47 s
- [X] SCN-001-T11 [US1] CMP-002 amendment: `LayerStack.init(restoring:)` and `LayerStackError.duplicateLayer` in `Packages/Compositor/Sources/Compositor/LayerStack.swift` with tests in `Packages/Compositor/Tests/CompositorTests/LayerStackTests.swift`; `LayerKind.material` in `Packages/Compositor/Sources/ProceduralMaterials/MaterialLayerKind.swift`; `LayerKind.generatorGraph` in `Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphLayerKind.swift` — Verified 2026-11-13: LayerStackTests 10/10 (testRestoringKeepsIDsAndOrderAndNeverReusesThem, testRestoringRefusesDuplicatesAndLimits) on the host and in the Linux shape; Compositor host 185/185
- [X] SCN-001-T12 [US1] Live adapters `SceneLiveState`, `SceneDocument(capturing:id:name:)`, `liveState(registry:assets:)`, `SceneCaptureError`, `SceneLoadError` in `Packages/SceneFormat/Sources/SceneFormat/SceneLiveState.swift` — Verified 2026-11-13: SceneLiveAdapterTests 4/4
- [X] SCN-001-T13 [US1] Live round-trip tests (every layer kind, saved instance IDs and next ID, parameters restored into a `ParameterStore`, bindings bound into an `AudioFeatureModulator`) in `Packages/SceneFormat/Tests/SceneFormatTests/SceneLiveAdapterTests.swift` (S2) — Verified 2026-11-13: SceneLiveAdapterTests.testLiveStateRoundTripsThroughCanonicalBytes (stack IDs and order, next ID, ParameterStore.restore, AudioFeatureModulator bindings, re-capture equal)

## Phase 4: User Story 2 — Damaged, hostile or newer scenes are refused or reported (P1)

**Goal**: every refusal and issue of contract C4/C5 with its exact message. **Independent test**: the validation table.

- [X] SCN-001-T14 [US2] Validation `validate(registry:assets:)` and `SceneAssetAvailability` in `Packages/SceneFormat/Sources/SceneFormat/SceneValidation.swift` (contract C5 order and messages; MOD-001 scratch store, MOD-002 scratch modulator, MOD-014 graph, SHD-009 compile, MED-009 and SHD-011 decoders) — Verified 2026-11-13: SceneValidationTests 6/6
- [X] SCN-001-T15 [P] [US2] Decode refusal table in `Packages/SceneFormat/Tests/SceneFormatTests/SceneDecodeErrorTests.swift` (every C4 case, exact message, size refused before parsing) — Verified 2026-11-13: SceneDecodeErrorTests.testRefusalsHaveExactMessages (26 cases), testOneMebibyteIsAcceptedAndNothingIsParsedBeyondIt
- [X] SCN-001-T16 [P] [US2] Validation table in `Packages/SceneFormat/Tests/SceneFormatTests/SceneValidationTests.swift` (every C5 code with its exact message, severity and path; clean fixture has no issue; errors block `liveState`, warnings do not; a modulation cycle names its path) — Verified 2026-11-13: SceneValidationTests 6/6 (exact code, path, message and severity per issue; errors block liveState, warnings do not; cycle path)
- [X] SCN-001-T17 [P] [US2] Limits and version tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneLimitTests.swift` (each count limit at limit and limit + 1, version 0, 1.5, 2, missing format) — Verified 2026-11-13: SceneDecodeErrorTests.testCountLimitsAreCheckedBeforeTypedDecoding (each limit at and over) and the version cases

## Phase 5: User Story 3 — Future versions extend the format without loss (P2)

- [X] SCN-001-T18 [US3] Forward-compatibility tests in `Packages/SceneFormat/Tests/SceneFormatTests/SceneForwardCompatibilityTests.swift`: unknown kind, unknown asset type, unknown fields at document, layer, binding and asset level round-trip byte for byte; unknown field in a transform dropped with a warning (S4) — Verified 2026-11-13: SceneForwardCompatibilityTests 2/2 (byte-identical round trip; dropped transform field warned)

## Phase 6: Polish

- [X] SCN-001-T22 [P] Source-safety test (R14, contract C7; analyze E1) in `Packages/SceneFormat/Tests/SceneFormatTests/SceneSourceSafetyTests.swift`: the module's sources contain no file, URL, network, process or dynamic-loading API (`FileManager`, `URL(`, `URLSession`, `Process`, `dlopen`, `NSExpression`, `fopen`) and no C stdio globals — Verified 2026-11-13: SceneSourceSafetyTests 2/2; check_compliance OK

- [X] SCN-001-T19 Linux shape run (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) of SceneFormat and Compositor's LayerStack tests; ParameterGraph tests unchanged (S5) — Verified 2026-11-13: SceneFormat 31/31 and Compositor LayerStack 10/10 in the Linux shape; ParameterGraph unchanged (not rerun)
- [X] SCN-001-T20 ADR `docs/adr/0028-scene-document-format.md`, ADR-0013 amendment note (CMP-002 restore), `docs/adr/README.md` index, test report `docs/test-reports/scene-format.md`, spec status — Verified 2026-11-13: files present; validate_docs OK
- [X] SCN-001-T21 `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py` — Verified 2026-11-13: check_compliance OK, validate_docs OK, test_scripts 111 OK (1 skipped)

## Dependencies

T01 → T02-T04 → T05 → T06 → US1 (T08-T13) → US2 (T14-T17) → US3 (T18) → T19-T21. T11 is
independent of T02-T10. Parallel: T02/T03/T04; T07 after T03-T04; T15/T16/T17 after T14.

## Implementation Strategy

MVP is US1 (format, codec, round trip, live adapters). US2 hardens it for untrusted files; US3
proves forward compatibility. Commit after each phase.

## Analysis (speckit-analyze, 2026-11-13)

| ID | Severity | Finding | Fix applied |
|---|---|---|---|
| E1 | MEDIUM | SCN-001-R14 (no files, network or execution) had no task that tests it. | Added SCN-001-T22 (source-safety test). |
| E2 | LOW | SCN-001-S5 (suite under 1 minute) is measured only by T19's run. | T20's test report records the suite durations. |
| F1 | LOW | "Missing asset" needs the app's stores; this row has none. | T14 defines `SceneAssetAvailability`; tests use a fake; the app adapter is SCN-002. |

Coverage: R1-R6 → T05/T06/T08/T09; R7 → T04/T09; R8 → T03/T05/T15/T17; R9 → T14/T16; R10 → T18;
R11-R12 → T11-T13/T16; R13 → T05/T09; R14 → T19/T22. S1 → T09/T10; S2 → T13; S3 → T15-T17; S4 →
T18; S5 → T19/T20. No constitution conflicts; 0 critical, 0 duplicates, 0 ambiguities left.
