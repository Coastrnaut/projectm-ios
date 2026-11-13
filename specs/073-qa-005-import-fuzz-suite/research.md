# Research: QA-005 Import Fuzz Suite

Decisions are numbered `QA-005-D1…`. Findings (crashes or hangs the suites found) are at the end.

## QA-005-D1: Where the harness and suites live

- **Decision**: a new test-only package `Packages/ImportFuzz` with a dependency-free library target
  `FuzzKit` and one test target `ImportFuzzTests` that depends on the parsers' existing products.
- **Rationale**: one harness for seven parsers in five packages; no parser manifest changes (FILE-010
  and SCN-003 edit SceneArchive/SceneFormat in parallel); CI adds one name to five loops. Public APIs
  only (no `@testable` across packages), so the suites exercise exactly what the app calls.
- **Alternatives**: (a) `FuzzKit` as its own package plus a suite in each parser's test target — five
  manifest edits and five corpora locations; rejected for parallel-merge risk. (b) Per-package copies —
  the duplication the audit already found (nine SplitMix64 copies). Migrating the existing per-parser
  fuzz tests to FuzzKit is a later cleanup.

## QA-005-D2: Determinism

- **Decision**: SplitMix64 (`FuzzRandom`); input *i* of a suite is derived from
  `mix(suiteSeed ^ FUZZ_SEED) + i`, so any input can be rebuilt from (seed, iteration) alone and
  suites do not depend on each other's order. A 64-bit FNV-1a digest of all inputs proves
  byte-identical runs (QA-005-S3).
- **Alternatives**: the standard library's `SystemRandomNumberGenerator` (not reproducible);
  `RandomNumberGenerator`-driven `Int.random(in:using:)` (its algorithm may change between Swift
  versions).

## QA-005-D3: What "hang" means

- **Decision**: work, not time. Each suite's body returns a `FuzzOutcome` with the work the parser
  reports when it reports any; the campaign checks `work ≤ bound(inputBytes)`:
  - BoundedJSON: `bytesExamined ≤ inputBytes` (FILE-007-R4), and = inputBytes on acceptance.
  - Expressions: SHD-010 `ExpressionCompileWork.isWithinBounds` and `total ≤ ceiling(.standard)`
    (contract B4: ≤ 4,096).
  - Other parsers expose no counter. Their bound is structural: the harness caps every input at the
    parser's documented size limit (+1 byte to exercise the size refusal), every parser documents a
    single forward pass or bounded loops over that size, and the campaign's per-run byte budget bounds
    the total. A true infinite loop would never return, which the test runner's own timeout (CI
    `timeout-minutes`, `-default-test-execution-time-allowance 180` on simulators) reports; no test
    asserts a duration.
- **Alternatives**: wall-clock deadlines per call (flaky on shared CI runners, forbidden by the brief);
  instrumenting parsers with new counters (changes parser code without a finding; QA-005-R11).

## QA-005-D4: Budgets

| Suite | Default inputs | Input cap | Why |
|---|---|---|---|
| BoundedJSON | 3,000 | 4 KiB | Pure scan; cheap |
| Expression | 3,000 | 520 B (limit 512 + 8) | Cheap compile |
| OSC decoder + dispatcher | 4,000 | 1,473 B (limit + 1) | Cheap; two calls per input |
| Graph import | 600 | 8 KiB | `JSONDecoder` per accepted shape |
| Scene JSON | 800 | 16 KiB | Own reader + validation + restore |
| Scene archive | 300 | 64 KiB | SHA-256 per file, full reader |
| Preset validator | 300 | 16 KiB | Line/shader scans |
| Preset import (files) | 12 | 16 KiB | File writes per input |

`FUZZ_ITERATIONS=n` replaces every suite's default with `n` (the file-import suite uses `n / 25`, at
least 1), ceiling 100,000. The per-run byte budget is inputs × cap. Final numbers are set after
measuring on the Mac host (task QA-005-T14) and recorded here.

## QA-005-D5: Mutation strategies

Ten strategies, each choosing positions from the generator and capping output: `bitFlip`,
`byteOverwrite` (interesting bytes: 0x00, 0x7F, 0x80, 0xFF, quote, brackets, newline),
`byteInsert`, `byteDelete` (a run of 1-16), `truncate`, `repeatSlice` (a slice repeated until the
cap), `splice` (prefix of one corpus item + suffix of another), `lengthField` (a 16- or 32-bit LE/BE
field at an aligned offset set to 0, 1, max, size±1 or a random value — hits ZIP headers and OSC
sizes), `jsonStructure` (insert `[`/`{` runs, delete a quote, replace a number/literal token, swap
`:`/`,`), `oscStructure` (rewrite a type-tag byte to another tag, break 4-byte padding, set a blob
size). Each input applies 1-4 stacked strategies to a corpus item (or, 1 in 16, to random bytes).
Suites choose the strategies that apply to their format; the archive suite adds a suite-local
"re-zip" strategy (mutate `manifest.json` or `scene.json`, then rewrite a checksum-valid archive) so
mutations reach the manifest and scene layers behind the ZIP checks.

## QA-005-D6: Corpus

Generated once with the repository's own builders (PRE-012 preset fixture text, OSC encoder, SCN-001
fixture scenes, FILE-001 archive writer, SHD-002 examples, SHD-009 fixture formulas, FILE-007 shapes),
written as files and checked in. A test checks the size budget and per-format counts (QA-005-S4).

## Findings

Recorded by QA-005-T15 after the first full default run and one `FUZZ_ITERATIONS=5000` run.
