# Tasks: QA-005 Import Fuzz Suite

**Input**: design documents in `specs/073-qa-005-import-fuzz-suite/` (spec, plan, research, data-model,
contracts/fuzz-harness.md, quickstart)

**Tests**: this feature *is* tests; each suite is its own verification. Every task runs on the Mac
host (`[Mac]`) and in the Linux shape (`[Linux]`); none needs a simulator or a device (spec
Clarifications). Phase tags follow the roadmap's hardening phase (Plan Phase E+, autonomous run).

Format: `- [ ] QA-005-Tnn [P?] [Story?] description (requirements; contract)`

## Phase 1: Setup

- [ ] QA-005-T01 [Mac] [Linux] Create `Packages/ImportFuzz/Package.swift`: product `ImportFuzz` (target `FuzzKit`, no dependencies), test target `ImportFuzzTests` depending on `FuzzKit` and the products PresetLibrary, PerformanceControl, ParameterGraph, SceneFormat, SceneArchive, LocalPortability, Compositor, VisualGenerators (path dependencies), resources `.copy("Fixtures")` (QA-005-R10; plan)

## Phase 2: Foundational (harness; blocks all suites)

- [ ] QA-005-T02 [Mac] [Linux] `FuzzRandom` (SplitMix64; `next`, `below(n)` for n ≥ 1, `chance(oneIn:)`, `bytes(count:)`, `mix`) in `Packages/ImportFuzz/Sources/FuzzKit/FuzzRandom.swift` (QA-005-R1; H1)
- [ ] QA-005-T03 [Mac] [Linux] `FuzzMutation` with the ten strategies of research QA-005-D5; "`apply(to:other:rng:cap:)` returns ≤ `cap` bytes; total for every input (empty included)" in `Packages/ImportFuzz/Sources/FuzzKit/FuzzMutation.swift` (QA-005-R2, R3)
- [ ] QA-005-T04 [Mac] [Linux] `FuzzBudget` and `FuzzConfiguration` ("`FUZZ_ITERATIONS` positive decimal ≤ 100,000 (larger capped, others ignored); `FUZZ_SEED` decimal or `0x` hex") in `Packages/ImportFuzz/Sources/FuzzKit/FuzzBudget.swift` (QA-005-R3, R7; H2)
- [ ] QA-005-T05 [Mac] [Linux] `FuzzInput`, `FuzzOutcome`, `FuzzReport` (FNV-1a digest, strategy counts, violations), `FuzzCampaign.run` (derives input *i* from seed and iteration, caps, stops at input or byte budget, checks `workBound`, formats violations per H4) in `Packages/ImportFuzz/Sources/FuzzKit/FuzzCampaign.swift`; `FuzzCorpus` (directory in file-name order, hidden files skipped) in `Packages/ImportFuzz/Sources/FuzzKit/FuzzCorpus.swift` (QA-005-R1, R3, R4, R8; H1-H4)
- [ ] QA-005-T06 [Mac] [Linux] `FuzzKitTests`: same seed → same digest twice and different seed → different digest; every strategy respects the cap on empty, 1-byte and large inputs; the input budget and the byte budget each stop a run; configuration parsing (unset, "0", "-3", "abc", "250", "999999" → capped, "0x1F" seed); a work bound violation is reported with seed, iteration and strategies, in `Packages/ImportFuzz/Tests/ImportFuzzTests/FuzzKitTests.swift` (QA-005-S3; US3)
- [ ] QA-005-T07 [Mac] [Linux] Seed corpus, ≥ 3 items per format, ≤ 200 KB total, generated once from the repository's own builders and checked in under `Packages/ImportFuzz/Tests/ImportFuzzTests/Fixtures/Corpus/{preset,osc,scene,archive,graph,expression,json}/`; `FuzzTestSupport.swift` (corpus loading, registry, `assertClean(report)`), and a corpus budget test in `FuzzKitTests` (QA-005-R5, S4)

## Phase 3: User Story 1 — hostile import files (P1)

**Independent test**: `swift test --package-path Packages/ImportFuzz --filter 'Preset|SceneJSON|SceneArchive|GraphImport'`

- [ ] QA-005-T08 [P] [US1] Preset suite: validator over mutated preset corpus (deterministic result per input), plus a file-import subset through `UserPresetLibrary.importFile(at:)` in a temporary directory (every outcome typed; library reloads with the same preset count), in `Packages/ImportFuzz/Tests/ImportFuzzTests/PresetFuzzTests.swift` (QA-005-R6)
- [ ] QA-005-T09 [P] [US1] Scene JSON suite: decode → on success `validate(registry:)`, `restoreModulation(registry:)`, and `encoded()` decodes again, in `Packages/ImportFuzz/Tests/ImportFuzzTests/SceneJSONFuzzTests.swift` (QA-005-R6)
- [ ] QA-005-T10 [P] [US1] Scene archive suite: byte, length-field and splice mutations plus the re-zip strategy (mutate `manifest.json` or `scene.json`, rewrite a checksum-valid archive), all through `SceneArchiveReader.read`, in `Packages/ImportFuzz/Tests/ImportFuzzTests/SceneArchiveFuzzTests.swift` (QA-005-R6)
- [ ] QA-005-T11 [P] [US1] Graph import suite: `GeneratorGraphImporter.importGraph(_:fileName:)`; accepted → `canonicalData` imports again to an equal document, in `Packages/ImportFuzz/Tests/ImportFuzzTests/GraphImportFuzzTests.swift` (QA-005-R6)

## Phase 4: User Story 2 — hostile OSC traffic (P1)

**Independent test**: `swift test --package-path Packages/ImportFuzz --filter OSCFuzzTests`

- [ ] QA-005-T12 [US2] OSC suite: `decodePacket` and `decode` per datagram (accepted packet re-encodes and decodes equal); the same datagrams through an `OSCDispatcher` on a fake clock and a manual scheduler (typed outcome; counters account for every datagram; stored value within [0, 1]), in `Packages/ImportFuzz/Tests/ImportFuzzTests/OSCFuzzTests.swift` (QA-005-R6)

## Phase 5: User Story 3 — reusable harness, other parsers, budgets (P2)

- [ ] QA-005-T13 [P] [US3] Expression suite (`CompiledExpression.measure`: SHD-010 bounds, compile twice equal) and BoundedJSON suite (`bytesExamined ≤ count`, `== count` on acceptance) in `Packages/ImportFuzz/Tests/ImportFuzzTests/ExpressionFuzzTests.swift` and `BoundedJSONFuzzTests.swift` (QA-005-R4, R6)
- [ ] QA-005-T14 [US3] Measure every suite on the Mac host (Debug), set the default budgets so each suite ≈ 2 s or less and the package < 10 s, record them in research QA-005-D4 (QA-005-R7, S2)
- [ ] QA-005-T15 [US3] On-demand run `FUZZ_ITERATIONS=5000`; fix any finding in its parser with a regression test there and the reproducer in the corpus; record findings in research.md (QA-005-R9, S5, S6)

## Phase 6: Polish

- [ ] QA-005-T16 [Mac] Append `ImportFuzz` to the five package loops in `.github/workflows/ios-ci.yml`; run `swift test` for ImportFuzz on the host and in the Linux shape, `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py` (QA-005-R10)
- [ ] QA-005-T17 Update the spec status, the roadmap row's status note if the roadmap tracks it, and the feature report in research.md (findings, budgets, durations) (QA-005-S1-S6)

## Dependencies

T01 → T02-T05 → T06, T07 → US1 (T08-T11, parallel), US2 (T12), US3 (T13) → T14 → T15 → T16 → T17.
User stories 1-3 are independent of each other once the harness and corpus exist.

## Implementation strategy

MVP: harness + corpus + US1 scene and archive suites (the untested paths). Then OSC, then the rest;
budgets are tuned once all suites exist.
