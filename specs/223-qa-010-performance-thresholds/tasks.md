# Tasks: QA-010 Performance budget thresholds

**Input**: Design documents from `specs/223-qa-010-performance-thresholds/` (spec, plan, research, data-model,
contracts/performance-thresholds.md, quickstart)

**Tests**: requested by the spec (fixture benchmark, QA-010-S1).

Format: `- [ ] QA-010-Tnn [P?] [Story] Description`. `{device}` = needs a physical device (left open).

## Phase 1: Setup

- [X] QA-010-T01 Create `docs/performance/` and `scripts/fixtures/qa010/` in the worktree — Verified 2026-11-14: both folders exist with content (`ls docs/performance scripts/fixtures/qa010`)

## Phase 2: Foundational (the budgets, blocks every story)

- [X] QA-010-T02 Write `docs/performance/thresholds.schema.json` (QA-010-R4; data-model "Thresholds file") — Verified 2026-11-14: `test_committed_thresholds_load_and_cover_every_class_and_metric` checks the schema's version const, required keys and per-metric directions against the checker's catalogue
- [X] QA-010-T03 Write `docs/performance/thresholds.json` version 1 with the Clarifications table: D1, D2, D3,
  `simulator` (evidence false), every limit with its basis (QA-010-R1-R3, S2) — Verified 2026-11-14: same test: classes D1, D2, D3, simulator with models from `rdt.DEVICES`, evidence [true, true, true, false], every limit has a basis

## Phase 3: User Story 1 — judge a measurement against the budget (P1) MVP

**Independent test**: `python3 scripts/test_scripts.py` runs `PerformanceThresholdsTests` green.

- [X] QA-010-T04 [US1] `scripts/check_performance_thresholds.py`: thresholds loader and structural validation
  (schema version, catalogue, directions, unique ids and models, pinned version) — contract C2 — Verified 2026-11-14: `test_unknown_class_wrong_version_and_mixed_models_are_errors` (schema version 2 refused, pinned 2 vs 1 refused)
- [X] QA-010-T05 [US1] Input recognition and extraction (PERF-012, perf001, sc015; worse-value merge; model
  resolution, `--device`/`--model`/`--simulator`) — contract C3 — Verified 2026-11-14: `test_each_kind_of_fail_fails_only_its_metric`, `test_missing_metrics_read_not_measured_never_pass` (worse drop value from two inputs, invalid value), mixed models and no-model errors
- [X] QA-010-T06 [US1] Evaluator, verdict JSON/text, CLI and exit codes — contract C4, QA-010-R6-R8, R10 — Verified 2026-11-14: `test_pass_fixture_passes_every_metric_with_the_version`, `test_cli_writes_the_verdict_and_returns_the_exit_code` (exit 0 and 1), error cases exit 2
- [X] QA-010-T07 [P] [US1] Fixture benchmark in `scripts/fixtures/qa010/`: D1 pass (PERF-012 + perf001 with
  `audioAgeP95Ms` + sc015), fails for frame rate, frame percentile, drops, memory, launch; a missing-metric report;
  an unknown-model report; a thresholds file of the wrong schema version — Verified 2026-11-14: 14 fixtures in `scripts/fixtures/qa010/`, used by the 9 `PerformanceThresholdsTests`
- [X] QA-010-T08 [US1] `PerformanceThresholdsTests` in `scripts/test_scripts.py`: each fixture's expected
  verdict, determinism (two runs byte-identical), boundary (value = limit passes), committed thresholds file
  matches its schema's required keys and catalogue, simulator class says not evidence, pinned version mismatch,
  mixed models, an invalid (negative) value reads not measured, exit codes (QA-010-S1, S3) — Verified 2026-11-14: `python3 scripts/test_scripts.py`: 173 tests OK (1 skipped) in 16.4 s; the 9 QA-010 tests take 0.014 s

## Phase 4: User Story 2 — the final device stage step (P2)

**Independent test**: `run_device_tests.py --dry-run thresholds --device D1 --run` prints the device commands and
writes a verdict from the files present; covered by a unit test with a temporary export folder.

- [X] QA-010-T09 [US2] `thresholds` subcommand in `scripts/run_device_tests.py` (contract C5; `--simulator`
  forces the simulator class) — Verified 2026-11-14: `run_device_tests.py --dry-run thresholds --device D1 --run --no-install --report scripts/fixtures/qa010/perf012-d1-pass.json` printed the perf001 and 11 sc015 devicectl launches and the pull, judged the fixture (incomplete, exit 1) and wrote no verdict file
- [X] QA-010-T10 [US2] Unit test of the step's file selection and verdict writing (temporary folder, no device) — Verified 2026-11-14: `test_runner_step_picks_the_newest_reports_and_writes_the_verdict` (newest perf001 chosen, verdict file written and not re-read as input, simulator verdict not evidence)

## Phase 5: Polish

- [X] QA-010-T11 "Budgets (QA-010)" section in `docs/test-reports/performance.md` pointing to the thresholds file
  and the step; run the repo checks (compliance, docs, motion, permission catalogue, status events, script tests) — Verified 2026-11-14: section "Budgets per device class (QA-010)" added; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; script tests 173 OK
- [ ] QA-010-T12 {device} Run `run_device_tests.py thresholds --device <D> --run --report <PERF-012 export>` on
  D1, D2 and D3 and record the verdicts in `docs/test-reports/performance.md` (QA-010-S4)

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → T07/T08 → T09 → T10 → T11 → T12. T07 can be written alongside T04-T06.
