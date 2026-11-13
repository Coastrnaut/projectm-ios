# Feature Specification: QA-005 Import Fuzz Suite

**Feature Branch**: `feature/qa-005` (spec directory `073-qa-005-import-fuzz-suite`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (QA-005-T01-T17 verified on the Mac host, the Linux shape and the iOS 27.2 simulator; no finding, so no parser changed)

**Input**: User description: "Implement QA-005 (Import fuzz suite) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Fuzz preset, OSC and scene parsers
with bounded inputs." Acceptance, verbatim: "Corpus causes no crashes or hangs under configured fuzz
budget." P0, effort L, depends on FILE-007 (document schema validator) and OSC-002 (OSC message
parser). Verification: unit + simulator during development (no device)."

Identifiers in this feature carry the roadmap ID: requirements `QA-005-R1…`, success criteria
`QA-005-S1…`, tasks `QA-005-T01…`. Other features are cited by their own IDs: PRE-012 (user preset
import and its validator), OSC-001 / OSC-002 / OSC-009 (OSC decoder, dispatcher, rate limits), SCN-001
(scene document), MOD-013 (modulation restore), FILE-001 / FILE-002 (scene archive), FILE-007
(BoundedJSON), SHD-002 / SHD-011 (generator graphs and their import), SHD-009 / SHD-010 (expression
language and its counted compile work), MED-014 (media sniffers).

## Baseline: what is fuzzed today (audit of 2026-11-13, commit `578cac5`)

| Parser (entry point) | Untrusted source | Existing randomized test | Inputs per run | Seed corpus | Hang bound observed | Gap |
|---|---|---|---|---|---|---|
| OSC message decoder (`OSCDecoder.decode`) | UDP datagram | OSC-001 `OSCDecoderTests` fixed-seed fuzz | 20,000 | Built in code | Size limit only | No shared corpus; dispatcher not fuzzed |
| OSC packet decoder, bundles (`OSCDecoder.decodePacket`) | UDP datagram | OSC-002 `OSCPacketDecoderTests` structure-aware fuzz | ~24,000 | Generated packets | Depth/element limits | Same |
| OSC dispatcher (`OSCDispatcher.handle`) | UDP datagram | Hand-written cases and floods only | — | — | — | **Not fuzzed** |
| Milkdrop preset validator (`MilkdropPresetValidator.validate`) | Picked `.milk` file | PRE-012 `PresetMutationSweepTests` (10 mutation kinds) | 60 (600 on demand) | One fixture preset | Not counted | No small checked-in corpus; slow per variant |
| User preset import (`UserPresetLibrary.importFile`) | Picked `.milk` file | Sweep above goes through it | 60 | Same | Not counted | Covered, but only one base preset |
| Scene JSON decode (`SceneDocument.decode`) | Picked/archived `scene.json` | SCN-001 `ScenePropertyTests`: 500 random *valid* scenes round-trip; `SceneHostileInputTests`: hand cases | 500 | Generated | Depth/size limits | **Mutated bytes not fuzzed** |
| Scene validation (`validate(registry:)`) | Same | Only on valid round-trip scenes | 500 | — | — | **Not fuzzed on hostile decoded documents** |
| MOD-013 restore (`restoreModulation(registry:)`) | Same | `SceneModulationPropertyTests`: 200 random valid sections | 200 | Generated | — | **Not fuzzed on mutated documents** |
| Scene archive reader incl. ZIP (`SceneArchiveReader.read`) | Picked `.pmscene` | FILE-001 hostile hand cases (truncation, one flipped byte) | ~10 | One fixture archive | Size limit | **Not fuzzed** |
| Generator graph import (`GeneratorGraphImporter.importGraph`) | Picked `.json` | SHD-011 hostile hand cases; SHD-002 graph property tests (200 valid graphs) | ~20 | Examples | Size, nesting | **Mutated bytes not fuzzed** |
| Expression language (`CompiledExpression`) | Text in scenes and settings | SHD-009 `ExpressionFuzzTests`; SHD-010 counted compile work | 2,000 | Fixture formulas | SHD-010 work counters | Covered; no shared corpus |
| BoundedJSON (`BoundedJSON.check`) | Archive manifests, library files | FILE-007 `BoundedJSONFuzzTests` | 2,500 | Built in code | `bytesExamined` | Covered; no shared corpus |
| Media sniffers (`MediaSniffing`) | Picked photo/video | MED-014 `SnifferFuzzTests` | 2,700 | Fixture bytes | Bounded loops | Covered (out of this row's scope; listed for completeness) |

Existing randomized tests each carry their own copy of the same generator (nine copies of SplitMix64),
their own mutations and no common notion of a budget. Five import paths are not fuzzed with mutated
bytes at all.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the shared harness live? → A: In one new test-only package, `Packages/ImportFuzz`: a dependency-free library `FuzzKit` (generator, mutations, budget, hang guard, corpus loader) and one test target that depends on the parsers' existing products. No parser package gains a dependency or a manifest change (FILE-010 and SCN-003 edit those packages in parallel), and the existing per-parser fuzz tests stay where they are, unchanged.
- Q: What does "hang" mean without wall-clock asserts? → A: A parser call "hangs" when the work it reports, or the work bound the harness can derive from its input, exceeds a fixed linear bound of the input size. Where the parser counts its work (FILE-007 `bytesExamined`, SHD-010 compile work) the suite asserts that counter against the documented bound; elsewhere the parser's documented size limit bounds the input (every input is capped by the harness before the call) and the suite counts calls and bytes against a per-run budget. No test reads a clock.
- Q: What is the default budget? → A: Small enough for CI: every suite at most about 2 s on the Mac host in Debug and the whole package under 10 s (owner rule 7). A larger run is opt-in through the `FUZZ_ITERATIONS` environment variable (inputs per suite); nothing larger ever runs by default.
- Q: What goes into the corpus? → A: Small seed files written for this feature (valid and near-valid examples of each format, plus every reproducer found), under the test target's `Fixtures/Corpus/<parser>/`, at most 200 KB in total. No third-party preset text: the preset seeds are authored here and use only the syntax the repository's own fixtures already use.
- Q: Are random inputs saved or replayed? → A: Inputs are derived from (suite seed, iteration), so a failure message names the suite, seed, iteration and strategy, and the input can be rebuilt exactly; a reproducer worth keeping is copied into the corpus as a file.
- Q: What happens when the fuzz finds a crash or hang? → A: The parser is fixed with the smallest change, a regression test is added next to the parser's own tests, the input joins the corpus, and the finding is listed in the feature report (research).
- Q: Does the user preset import path write files? → A: Yes, into a fresh temporary directory per test (as PRE-012's own tests do) with no trial runner, so imports end quarantined, waiting or refused; the budget for this suite is the smallest because each input costs file writes.
- Q: Simulator? → A: Not needed: no app code changes and every parser builds and tests on the macOS host and in the Linux shape. Simulator runs of this package are therefore not required (recorded as such, not as passed). (Done anyway once, because CI runs every package on simulators: 15/15 on a temporary iOS 27.2 simulator, 10.1 s; research QA-005-D4.)
- Q: Should an input that a parser accepts be checked for more than "no crash"? → A: Yes, but only with an invariant the parser already promises, so no new behaviour is invented: an accepted scene re-encodes to bytes that decode again; an accepted graph's canonical bytes import again; an accepted expression compiles to the same bytes twice; an accepted BoundedJSON input reports `bytesExamined` equal to its length. A violation is a finding (QA-005-R9). Applied to QA-005-R6.
- Q: How large may `FUZZ_ITERATIONS` go? → A: Capped at 100,000 inputs per suite (a hard ceiling in the harness); 0, negative or non-numeric values are ignored and the default is used. Applied to QA-005-R7.
- Q: Can a developer explore a different input stream without editing code? → A: Yes: an optional `FUZZ_SEED` (decimal or `0x` hex) is mixed into every suite's fixed seed; unset, CI always uses the fixed seeds. Applied to QA-005-R1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hostile import files never crash or hang the app (Priority: P1)

A performer imports a preset, scene, scene archive or generator graph that was damaged in transit or
crafted to break the app. Whatever the bytes, the import ends with a typed result (accepted, warned,
quarantined or refused) and the app keeps running.

**Why this priority**: The row's acceptance: "Corpus causes no crashes or hangs under configured fuzz budget."

**Independent Test**: Run the import fuzz suites for preset text, scene JSON, scene archives and graph
files with the default budget; every input returns a typed result within the work bound.

**Acceptance Scenarios**:

1. **Given** the preset corpus and its mutations, **When** each is validated and a subset imported,
   **Then** each ends accepted, quarantined or refused, and the library stays readable.
2. **Given** the scene JSON corpus and its mutations, **When** each is decoded, validated and its
   modulation restored, **Then** each returns a document with issues or a typed decode error.
3. **Given** a valid scene archive and its mutations (bytes, ZIP fields, manifest JSON), **When** each
   is read, **Then** each is accepted or refused with a typed archive error.
4. **Given** the graph corpus and its mutations, **When** each is imported, **Then** each is accepted
   or refused with a typed import error.

### User Story 2 - Hostile OSC traffic never crashes the receiver (Priority: P1)

A device on the local network sends malformed or adversarial OSC datagrams. The decoder and the
dispatcher return a typed outcome for each and the receiver's counters stay consistent.

**Why this priority**: OSC is the only path that takes bytes from another device without a person
choosing a file.

**Independent Test**: Run the OSC suite: mutated datagrams from the OSC corpus go through the decoder
and through a dispatcher on a fake clock; every outcome is typed and counters add up.

**Acceptance Scenarios**:

1. **Given** the OSC corpus and its mutations, **When** each is decoded, **Then** each returns a
   message, a bundle or a typed decode error.
2. **Given** the same datagrams sent to a dispatcher, **When** each is handled, **Then** each returns
   a typed outcome, the counters account for every datagram, and the stored parameter value stays
   inside its declared range.

### User Story 3 - One reusable harness with a configurable budget (Priority: P2)

A developer adding a new parser writes a short suite with the shared harness: seeds from the corpus,
standard mutations, a budget, and a hang bound; CI runs it small, and a developer can run it large.

**Why this priority**: Makes the next parser cheap to fuzz and replaces nine private copies of the same
generator over time.

**Independent Test**: Harness self-tests: same seed gives the same inputs on every host; every mutation
respects the size cap; the budget stops a run at its limits; `FUZZ_ITERATIONS` changes the count.

**Acceptance Scenarios**:

1. **Given** a seed, **When** the harness generates inputs twice, **Then** the inputs are identical.
2. **Given** a size cap, **When** any mutation runs, **Then** its output never exceeds the cap.
3. **Given** `FUZZ_ITERATIONS` unset, **When** suites run, **Then** each uses its small default; when
   set to a number, each uses that number (bounded by a hard ceiling).

### Edge Cases

- An empty input, a single byte, an input exactly at a parser's size limit and one byte over.
- A mutation that produces valid input again (accepted inputs are part of a healthy run, not an error).
- Splicing two corpus items of different formats into one input.
- Length fields (ZIP sizes and offsets, OSC string padding and blob sizes) set to 0, the maximum, and
  values that point past the end.
- Deep nesting and repeated sections that grow an input towards its limit.
- `FUZZ_ITERATIONS` set to a non-number, zero, or a huge number (ignored, ignored, capped).

## Requirements *(mandatory)*

### Functional Requirements

- **QA-005-R1**: A shared fuzz harness MUST generate inputs deterministically from a 64-bit seed so the
  same seed gives the same inputs on every supported host; the generator MUST NOT use the standard
  library's random sources. An optional `FUZZ_SEED` environment value is mixed into every suite's
  fixed seed for on-demand exploration; unset, the fixed seeds are used.
- **QA-005-R2**: The harness MUST offer these mutation strategies: bit flip, byte overwrite, byte
  insert, byte delete, truncation, repetition of a slice, splice of two corpus items, length-field
  tweaks (little- and big-endian 16/32-bit fields set to edge values), and structural mutations for
  JSON (bracket and quote insertion, value replacement, deep nesting) and OSC (type-tag and padding
  changes).
- **QA-005-R3**: Every generated input MUST be capped at a per-suite maximum size, and each run MUST
  stop at a per-run budget of inputs and of total bytes processed.
- **QA-005-R4**: Each parser call MUST be checked against a hang bound expressed as work, never as
  time: the parser's own work counter against its documented linear bound where one exists, otherwise
  the per-input size cap plus the per-run budget.
- **QA-005-R5**: A checked-in seed corpus MUST exist for each fuzzed format (preset text, OSC packets,
  scene JSON, scene archives, generator graphs, expressions, bounded JSON), authored for this feature
  or taken from the repository's own fixtures, at most 200 KB in total.
- **QA-005-R6**: Suites MUST exist for: preset text (validator for every input, the user preset import
  path for a subset), OSC (decoder and dispatcher), scene JSON (decode, validation, modulation
  restore), scene archives (the full archive reader including ZIP parsing), generator graph import,
  the expression language, and BoundedJSON. Each suite MUST assert that every input yields a typed
  result, and that an accepted input keeps the invariant its parser already promises (scene: re-encode
  decodes again; graph: canonical bytes import again; expression: compiles to the same bytes twice;
  BoundedJSON: an accepted input was examined to its last byte).
- **QA-005-R7**: Default budgets MUST keep each suite at about 2 s or less and the whole package under
  10 s on the Mac host in Debug; `FUZZ_ITERATIONS` MUST raise or lower the inputs per suite, capped at
  100,000, and zero, negative or non-numeric values MUST be ignored.
- **QA-005-R8**: A failure MUST report the suite, seed, iteration, strategy and input size, so the
  input can be rebuilt exactly.
- **QA-005-R9**: Any crash or hang the suites find MUST be fixed in the parser with the smallest
  change, with a regression test in the parser's own package and the reproducer added to the corpus.
- **QA-005-R10**: The suites MUST build and pass on the macOS host and in the Linux shape, and CI MUST
  run the new package in every package loop.
- **QA-005-R11**: The feature MUST NOT change any parser's accepted inputs, refusals or messages except
  to fix a finding under QA-005-R9.

### Key Entities

- **Fuzz seed**: a 64-bit value naming a suite's deterministic stream of inputs.
- **Mutation strategy**: one named transformation from corpus items to a new input.
- **Fuzz budget**: inputs per run, total bytes per run, maximum bytes per input.
- **Corpus item**: a small checked-in file that is a valid or near-valid example of one format.
- **Finding**: a crash or hang with its reproducer, fix and regression test.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-005-S1**: With the default budget, every suite processes its inputs and every input returns a
  typed result: zero crashes, zero traps, zero hang-bound violations across all seven suites.
- **QA-005-S2**: The whole fuzz package finishes in under 10 s on the Mac host (Debug) and each suite in
  about 2 s or less.
- **QA-005-S3**: Running the same suite twice with the same seed processes byte-identical inputs
  (checked by a digest of all inputs).
- **QA-005-S4**: The checked-in corpus is at most 200 KB and has at least 3 items per format.
- **QA-005-S5**: Every finding (if any) has a regression test and a corpus reproducer, and is listed in
  the research document.
- **QA-005-S6**: A run with `FUZZ_ITERATIONS=5000` completes with zero crashes or hang-bound violations
  (on demand, reported once; not part of CI).

## Assumptions

- The parsers' documented size limits (OSC 1,472 bytes, preset 512 KiB, scene 1 MiB, archive limits,
  graph 64 KiB, expression 512 bytes, BoundedJSON per schema) are the hang bound's input cap; the
  harness never feeds an input larger than the parser accepts by more than one byte except to test the
  size refusal itself.
- Existing per-parser fuzz tests stay as they are; migrating them onto the shared harness is a later
  cleanup, not part of this row.
- The media sniffers (MED-014) are outside this row's "preset, OSC and scene parsers" and are not
  re-fuzzed here.
- No app target changes, so no simulator or device run is needed (row verification: unit + simulator
  during development; the simulator part is not applicable and recorded as such).
