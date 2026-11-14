# Implementation Plan: QA-010 Performance budget thresholds

**Branch**: `feature/qa-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A committed, versioned budget file (`docs/performance/thresholds.json`, contract
`docs/performance/thresholds.schema.json`) declares seven metrics and their limits for the device classes D1, D2,
D3 and a not-evidence simulator/host class. A standard-library Python checker
(`scripts/check_performance_thresholds.py`) reads PERF-012 performance reports, AutomationRunner `perf001` reports
and `sc015` launch samples, and writes a deterministic per-metric pass/fail/not-measured verdict naming the
thresholds version. `scripts/run_device_tests.py thresholds` runs it on demand at the final device stage. Fixture
reports in `scripts/fixtures/qa010/` plus tests in `scripts/test_scripts.py` are the acceptance benchmark.

## Technical Context

**Language/Version**: Python 3 (standard library only; the scripts' existing baseline)
**Primary Dependencies**: none new; reads the PERF-012 report (schema version 1) and AutomationRunner JSON
**Storage**: committed JSON files under `docs/performance/`; verdicts next to pulled reports (device exports)
**Testing**: `python3 scripts/test_scripts.py` (unittest), fixtures under `scripts/fixtures/qa010/`
**Target Platform**: the Mac (and any OS for the checker and its tests); devices only through the runner step
**Project Type**: tooling + documentation; no app, package or project.yml change
**Performance Goals**: the checker's tests run in well under a second in total
**Constraints**: deterministic output; missing metric never passes; simulator never evidence
**Scale/Scope**: 4 classes × 7 metrics; ~10 fixture cases

## Constitution Check

- Public APIs / no networking in the app: unaffected (no app code). PASS
- Evidence (simulator never evidence, report honestly): the simulator class is `evidence: false` and every
  verdict says so; device verdicts are an open `{device}` task. PASS
- Short tests (owner rule 7): pure-function tests on small fixtures. PASS
- Privacy: verdicts carry only metrics, model and input file names. PASS

## Project Structure

```text
docs/performance/thresholds.json              # the versioned budgets (QA-010-R1-R3)
docs/performance/thresholds.schema.json       # its JSON Schema contract (QA-010-R4)
scripts/check_performance_thresholds.py       # loader, extractors, evaluator, CLI (R5-R8, R10)
scripts/run_device_tests.py                   # + `thresholds` subcommand (R9)
scripts/fixtures/qa010/*.json                 # fixture benchmark inputs
scripts/test_scripts.py                       # + PerformanceThresholdsTests
docs/test-reports/performance.md              # + a short "Budgets (QA-010)" pointer section
```

## Phases

- Research: [research.md](research.md). Data model: [data-model.md](data-model.md). Contract:
  [contracts/performance-thresholds.md](contracts/performance-thresholds.md). Quickstart:
  [quickstart.md](quickstart.md).
