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
- **Host note**: the byte strategies use only the generator and are identical on every host. The
  value-level JSON mutation (`FuzzJSON`, D5) re-serializes with Foundation's `JSONSerialization`,
  whose number formatting can differ between Darwin and Linux, so the suites that use it (scene JSON,
  scene archive, graph import, BoundedJSON) are byte-identical run to run on one host and may differ
  between hosts. A finding is reproduced on the host that reported it.
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

| Suite | Default inputs | Input cap | Mac host (Debug) | Linux shape | iOS 27.2 simulator |
|---|---|---|---|---|---|
| BoundedJSON | 3,000 | 4 KiB | 0.30 s | — | 2.18 s |
| Expression | 3,000 | 520 B (limit 512 + 8) | 0.19 s | — | 0.60 s |
| OSC decoder + dispatcher | 4,000 | 1,473 B (limit + 1) | 0.19 s | — | 0.37 s |
| Graph import | 600 | 8 KiB | 0.21 s | — | 0.94 s |
| Scene JSON (+ validation, restore) | 800 | 16 KiB | 0.81 s | — | 2.76 s |
| Scene archive | 300 | 64 KiB | 0.47 s | — | 1.13 s |
| Preset validator | 300 | 16 KiB | 0.32 s | — | 0.92 s |
| Preset import (files) | 40 | 16 KiB | 0.21 s | — | 0.79 s |
| **Package (15 tests)** | | | **2.7-2.8 s** | **3.3 s** | **10.1 s** |

Measured 2026-11-13 on the Mac Studio (`swift test`; Linux shape with the three `-D` flags and its
own scratch path; simulator: `xcodebuild test` on a temporary iPhone 17 / iOS 27.2 simulator, deleted
afterwards, no new PosterBoard reports: 32 before and after). The import subset went from 12 to 40
inputs after measuring (0.08 s at 12). `FUZZ_ITERATIONS=n` replaces every suite's default with `n`
(the file-import suite uses `n / 25`, at least 1), ceiling 100,000. The per-run byte budget is
inputs × cap.

## QA-005-D5: Mutation strategies

Ten strategies, each choosing positions from the generator and capping output: `bitFlip`,
`byteOverwrite` (interesting bytes: 0x00, 0x7F, 0x80, 0xFF, quote, brackets, newline),
`byteInsert`, `byteDelete` (a run of 1-16), `truncate`, `repeatSlice` (a slice repeated until the
cap), `splice` (prefix of one corpus item + suffix of another), `lengthField` (a 16- or 32-bit LE/BE
field at an aligned offset set to 0, 1, max, size±1 or a random value — hits ZIP headers and OSC
sizes), `jsonStructure` (insert `[`/`{` runs, delete a quote, replace a number/literal token, swap
`:`/`,`), `oscStructure` (rewrite a type-tag byte to another tag, break 4-byte padding, set a blob
size). Each input applies one strategy half the time, otherwise 2-4 stacked, to a corpus item (or,
1 in 16, to random bytes); the corpus items themselves come first, unchanged. Byte strategies mostly
break the grammar, so `FuzzJSON` adds value-level mutations (replace, delete, duplicate, wrap or copy
one value, key or element of a parsed document, then re-serialize): with them the scene suite's
accepted share rose from 8 of 800 inputs to 133.
Suites choose the strategies that apply to their format; the archive suite adds a suite-local
"re-zip" strategy (mutate `manifest.json` or `scene.json`, then rewrite a checksum-valid archive) so
mutations reach the manifest and scene layers behind the ZIP checks.

## QA-005-D6: Corpus

Generated once with the repository's own builders (PRE-012 preset fixture text, OSC encoder, SCN-001
fixture scenes, FILE-001 archive writer, SHD-002 examples, SHD-009 fixture formulas, FILE-007 shapes),
written as files and checked in. A test checks the size budget and per-format counts (QA-005-S4).

## Findings

**No crash, trap, hang-bound violation or broken invariant was found** (2026-11-13), so no parser
changed (QA-005-R9 had nothing to fix; `git diff autonomous/integration -- Packages ':!Packages/ImportFuzz'`
is empty). Runs:

| Run | Inputs | Result |
|---|---|---|
| Default budget (CI), Mac host | 12,040 across 8 suites | 0 violations |
| `FUZZ_ITERATIONS=5000` (all suites; import subset 200) | 35,200 | 0 violations; 21.5 s |
| `FUZZ_SEED=0xABCDEF FUZZ_ITERATIONS=20000` (all but archive and import) | 120,000 | 0 violations; 50.9 s |

Observed bounds: BoundedJSON never examined more bytes than its input (max 4,096 = the cap);
expression compile work peaked at 1,243 steps (ceiling 3,858, contract B4 ≤ 4,096). Accepted inputs at
the 5,000 run: scene JSON 769, archive 192 (40 distinct refusal kinds, from ZIP structure through
manifest, checksums, scene decode, validation and asset content), graph 249, OSC 294 (15 distinct
decode refusals; dispatcher counters always matched the outcomes), preset 1,414.

Because nothing was found, the corpus holds no reproducer yet; `quickstart.md` says where one goes.
