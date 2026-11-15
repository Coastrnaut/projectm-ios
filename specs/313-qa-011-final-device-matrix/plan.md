# Implementation Plan: QA-011 Final physical device matrix

**Branch**: `feature/qa-011` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Two standard-library Python tools. `scripts/qa011_inventory.py` parses every `specs/*/tasks.md`, lists each
unchecked `{device}`/`{owner}` task, classifies it (a scriptable / b person at the device / c owner-only away from
devices) with explicit rules, assigns devices and an owner session, and writes the committed inventory
(`docs/test-reports/qa-011/device-inventory.json`) and owner checklist (`owner-checklist.md`); `--check` fails when
either is stale. `scripts/run_device_matrix.py` runs every category (a) case per device (AutomationRunner modes,
launch modes, the QA-010 judge, on-device XCTest suites and benches) by reusing `run_device_tests.Target`, and
writes a hashed run record per device with OS/build, app build and commit, code-signature identity and team, case
results and artifact hashes. `run_device_tests.py matrix` forwards to it. Tests in `scripts/test_scripts.py`
cover parser, classifier, sessions, dry-run commands, hashing and the record writer with fixtures in
`scripts/fixtures/qa011/`. A simulator rehearsal (own simulator, deleted after) proves the runner end to end and
is committed as "not evidence".

## Technical Context

**Language/Version**: Python 3 (standard library only, as the other scripts)
**Primary Dependencies**: `scripts/run_device_tests.py` (Target, devicectl helpers, QA-010 judge),
`scripts/check_performance_thresholds.py`; Xcode 27.2 tools (`xcodebuild`, `xcrun devicectl`, `xcrun simctl`,
`codesign`, `xcresulttool`)
**Storage**: committed JSON/Markdown under `docs/test-reports/qa-011/`; bulky artifacts under `Build/qa-011/`
(gitignored)
**Testing**: `python3 scripts/test_scripts.py` (unittest); fixtures under `scripts/fixtures/qa011/`
**Target Platform**: the Mac; devices D1-D3 only in the owner's final stage
**Project Type**: tooling + documentation; no app, package or project.yml change
**Performance Goals**: inventory generation < 2 s over 313 specs; unit tests < 10 s in total
**Constraints**: never change signing; never touch D1-D3 from an agent; simulator never evidence; deterministic
inventory bytes
**Scale/Scope**: 263 open tagged tasks, 222 specs, 3 devices, ~16 matrix cases, 13 owner sessions

## Constitution Check

- I (public APIs) / no networking in the app: no app code changes. PASS
- X (evidence-based quality): simulator records say "simulator rehearsal, not evidence"; device runs stay open
  `{device}` tasks; inventory reports counts as found (263, not the brief's estimate). PASS
- Signing is manual: package tests use the committed include-only `Configs/Signing.xcconfig`; nothing writes
  signing settings; codesign is only read. PASS
- Short tests (owner rule 7): pure-function tests on small fixtures; the rehearsal is an on-demand run. PASS
- Privacy: records carry device model, OS, devicectl identifiers and the signing identity name already in the
  owner's certificate; no personal data beyond the device names the project already records in
  `docs/test-reports/devices.md`. PASS

Post-design re-check: unchanged, PASS.

## Project Structure

```text
scripts/qa011_inventory.py              # parser, classifier, sessions, checklist, --check (R1-R5)
scripts/run_device_matrix.py            # matrix cases, runner, record writer, hashing (R6-R11)
scripts/run_device_tests.py             # + `matrix` passthrough (R11)
scripts/fixtures/qa011/                 # fixture tasks.md files and a devicectl listing
scripts/test_scripts.py                 # + QA011InventoryTests, QA011MatrixTests
docs/test-reports/qa-011/device-inventory.json   # generated (R3)
docs/test-reports/qa-011/owner-checklist.md      # generated (R5)
docs/test-reports/qa-011/runs/sim/<run-id>/      # simulator rehearsal record (not evidence)
docs/test-reports/final-device-matrix.md         # the feature's test report
```

## Phases

- Research: [research.md](research.md). Data model: [data-model.md](data-model.md). Contract:
  [contracts/run-record.md](contracts/run-record.md). Quickstart: [quickstart.md](quickstart.md).
