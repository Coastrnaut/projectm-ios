# Contract: FuzzKit harness and the import fuzz suites (QA-005)

## H1 Determinism

`FuzzCampaign(name:seed:…).run(body)` presents the same inputs, in the same order, on every host and
every run with the same configuration. Input *i* uses `FuzzRandom(state: mix(seed ^ seedOverride) &+ UInt64(i))`.
`FuzzReport.digest` is FNV-1a 64 over every input's length (LE 64-bit) followed by its bytes.

## H2 Caps and budgets

- Every input has at most `budget.maxInputBytes` bytes. A suite may set the cap one byte above its
  parser's size limit so the size refusal itself is exercised.
- A run stops after `budget.inputs` inputs or when the bytes presented reach `budget.maxRunBytes`.
- `FuzzConfiguration` from the environment: `FUZZ_ITERATIONS` (1…100,000, larger capped, anything else
  ignored) replaces `budget.inputs`; `FUZZ_SEED` (decimal or `0x` hex) is XOR-ed into every seed.

## H3 Outcomes and the hang bound

The body returns `FuzzOutcome.accepted(work:)` or `.refused(work:)`, optionally with a `violation`.
When the campaign has a `workBound` and the outcome reports work, `work > workBound(input.count)` is a
violation ("hang bound"). A body that traps fails the test process (that is the crash signal); a body
never catches a trap. No duration is measured.

## H4 Failure report

Each violation string is `"<suite> seed=0x… iteration=N strategies=[…] base=K size=B: <reason>"`.
Suites assert `report.violations.isEmpty` and print at most the first 10.

## Suites (all public entry points; no `@testable`)

| Suite | Entry points | Typed result | Accepted-input invariant | Work bound |
|---|---|---|---|---|
| Preset | `MilkdropPresetValidator.validate(_:knownTextures:)`; `UserPresetLibrary.importFile(at:)` (subset) | `PresetValidation`; `PresetImportOutcome` | Validation is deterministic (same bytes → equal result); library reloads with the same count | Input cap |
| OSC | `OSCDecoder.decodePacket`, `OSCDecoder.decode`, `OSCDispatcher.handle` | `Result<OSCPacket, OSCDecodeError>`; `OSCDispatchOutcome` | Accepted packet re-encodes and decodes equal; dispatcher counters account for every datagram; stored value within [0, 1] | Input cap (1,472 + 1) |
| Scene JSON | `SceneDocument.decode`, `validate(registry:)`, `restoreModulation(registry:)` | `SceneDecodeResult` or `SceneDecodeError`; `[SceneIssue]`; `SceneModulationRestore` | `encoded()` decodes again | Input cap |
| Scene archive | `SceneArchiveReader.read(_:registry:)` | `SceneArchiveContents` or `SceneArchiveError` | — | Input cap |
| Graph import | `GeneratorGraphImporter.importGraph(_:fileName:)` | `ImportedGeneratorGraph` or `GeneratorGraphImportError` | `canonicalData` imports again to an equal document | Input cap (64 KiB) |
| Expression | `CompiledExpression.measure(source:)` | `Result<CompiledExpression, ExpressionError>` | Compiling twice gives equal bytes | SHD-010 B4: `isWithinBounds`, total ≤ ceiling |
| BoundedJSON | `BoundedJSON.check(_:limits:)` | `JSONShapeOutcome` | `bytesExamined == count` | `bytesExamined ≤ count` |
