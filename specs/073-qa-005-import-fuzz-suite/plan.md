# Implementation Plan: QA-005 Import Fuzz Suite

**Branch**: `feature/qa-005` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/073-qa-005-import-fuzz-suite/spec.md`

## Summary

One new test-only package, `Packages/ImportFuzz`, holds the shared harness and the seven suites
(spec baseline: five import paths had no mutated-byte fuzz; two were covered but without a shared
corpus or harness):

1. **`FuzzKit`** (library target, no dependencies, Foundation only at the edges): `FuzzRandom`
   (SplitMix64), `FuzzMutation` (ten strategies, every output capped), `FuzzBudget` and
   `FuzzConfiguration` (`FUZZ_ITERATIONS`, `FUZZ_SEED`, hard ceiling 100,000), `FuzzCampaign` (drives
   a suite: derives each input from seed and iteration, applies the per-input cap and per-run
   budgets, checks each outcome's reported work against the suite's linear work bound, collects
   violations with seed/iteration/strategy/size, and a digest of all inputs), `FuzzCorpus` (loads
   `Fixtures/Corpus/<format>/` in name order).
2. **`ImportFuzzTests`** (test target): `FuzzKitTests` (determinism, caps, budgets, configuration
   parsing) and one suite per format — preset text (validator + user preset import), OSC (decoder +
   dispatcher on a fake clock and a manual scheduler), scene JSON (decode, validate, MOD-013 restore,
   re-encode invariant), scene archive (bytes, ZIP length fields, and a re-zip strategy that mutates
   `manifest.json`/`scene.json` inside a checksum-valid archive), generator graph import (canonical
   re-import invariant), expressions (SHD-010 work counters against contract B4), BoundedJSON
   (`bytesExamined` bound).
3. **Corpus**: `Packages/ImportFuzz/Tests/ImportFuzzTests/Fixtures/Corpus/{preset,osc,scene,archive,graph,expression,json}/`,
   authored here (generated once from the repository's own fixture builders and examples, then checked
   in as files), ≤ 200 KB total, ≥ 3 items per format.
4. **CI**: `ImportFuzz` appended to the five package loops in `.github/workflows/ios-ci.yml`.
5. **Findings**: any crash/hang is fixed in its parser package with a regression test there, its
   reproducer added to the corpus, and listed in research.md (QA-005-R9).

No parser package's manifest or sources change unless a finding requires it. No app code changes, so
no simulator run is needed (spec Clarifications).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac; Xcode 26 and Linux in CI: explicit
closure types, no long untyped numeric expressions, no C stdio globals, no main-actor mutation in
setUp/tearDown, no wall-clock asserts)

**Primary Dependencies**: none new outside the repository; the test target depends by path on
PresetLibrary, PerformanceControl, ParameterGraph, SceneFormat, SceneArchive, LocalPortability,
Compositor and VisualGenerators (for the MOD-001 registry)

**Storage**: temporary directories only (user preset import suite), removed in teardown blocks

**Testing**: XCTest via `swift test --package-path Packages/ImportFuzz` on the Mac host and the Linux
shape (`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
--scratch-path .build/linuxshape`); CI also runs it in the Linux job, on simulators and builds it for
generic iOS

**Target Platform**: macOS host, Linux, iOS simulator (CI)

**Project Type**: test package (Swift Package Manager)

**Performance Goals**: each suite ≈ 2 s or less, package < 10 s on the Mac host in Debug (owner rule 7)

**Constraints**: deterministic (no clock, no system RNG); inputs capped per parser; corpus ≤ 200 KB

**Scale/Scope**: 8 test classes, ~10 harness types, ~25-35 corpus files

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I. Public Apple APIs only | Plain Swift and Foundation; no private API, no `dlopen` | Pass |
| VI. Modular boundaries | Test-only package; no parser depends on it; no app change | Pass |
| VII. Real-time audio safety | Not touched | N/A |
| IX. Pinned dependencies / untrusted presets | No third-party content; preset corpus authored here; user-imported presets treated as untrusted (that is what is fuzzed) | Pass |
| X. Evidence-based quality | Unit tests on the host and Linux shape; no device claims | Pass |
| Security: imported files untrusted, fail gracefully | The feature's purpose; findings fixed in the parser | Pass |
| Workflow: tasks tagged with phase and host needs | tasks.md tags every task `[Mac]`/`[Linux]`; none needs a device | Pass |

Post-design re-check: unchanged (Pass). No constitution default is overridden, so no ADR is needed;
the package choice is recorded in research.md (QA-005-D1).

## Project Structure

### Documentation (this feature)

```text
specs/073-qa-005-import-fuzz-suite/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/fuzz-harness.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/ImportFuzz/
├── Package.swift
├── Sources/FuzzKit/
│   ├── FuzzRandom.swift
│   ├── FuzzMutation.swift
│   ├── FuzzBudget.swift          # FuzzBudget + FuzzConfiguration
│   ├── FuzzCampaign.swift        # FuzzInput, FuzzOutcome, FuzzReport, FuzzCampaign
│   └── FuzzCorpus.swift
└── Tests/ImportFuzzTests/
    ├── Fixtures/Corpus/<format>/…
    ├── FuzzKitTests.swift
    ├── FuzzTestSupport.swift      # corpus access, registry, assertion helper
    ├── PresetFuzzTests.swift
    ├── OSCFuzzTests.swift
    ├── SceneJSONFuzzTests.swift
    ├── SceneArchiveFuzzTests.swift
    ├── GraphImportFuzzTests.swift
    ├── ExpressionFuzzTests.swift
    └── BoundedJSONFuzzTests.swift
.github/workflows/ios-ci.yml        # ImportFuzz in the five package loops
```

**Structure Decision**: one new package (research QA-005-D1). The parser packages are untouched unless
a finding needs a fix, which goes into that parser's package with its regression test.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| A new package (21st) | A shared harness for seven parsers in five packages | Per-package copies repeat the harness (the problem the audit found); adding a test dependency to five parser manifests collides with FILE-010/SCN-003 work in parallel |
