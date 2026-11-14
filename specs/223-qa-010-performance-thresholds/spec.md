# Feature Specification: QA-010 Performance budget thresholds

**Feature Branch**: `feature/qa-010` (spec directory `223-qa-010-performance-thresholds`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (QA-010-T01-T11 verified by `python3 scripts/test_scripts.py`, 9
PerformanceThresholdsTests on the fixture benchmark). Open: T12 `{device}` (verdicts on D1-D3). No device result is claimed.

**Input**: User description: "Implement QA-010 (Performance budget thresholds) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Declare per-device-class target FPS, memory and frame percentiles." Acceptance,
verbatim: "Fixture benchmark emits pass/fail against versioned thresholds." P1; depends on PERF-001."

Identifiers carry the roadmap ID: requirements `QA-010-R1…`, success criteria `QA-010-S1…`, tasks `QA-010-T01…`.
Other features are cited by their own IDs: SC-005, SC-008, SC-013, SC-015 (feature 001 Stage 2 criteria), R-06
(audio latency budgets, feature 001 research), FR-049 (quality governor floor), PERF-001 (stage timings), PERF-007
(frame drop telemetry), PERF-012 (performance report), QA-006 (render soak).

## Baseline: what exists today (audit of 2026-11-14, commit `637d6a54`)

| Area | Today |
|---|---|
| Targets | Written in prose only: SC-005 (≥ 55 fps for 95% of 1 s windows on D1, 60 fps cap), SC-008 (peak < 300 MB on D1; D2, D3 "measured and published"), SC-013 (FR-049 floor 30 fps on D1 and D3), SC-015 (cold launch < 2 s D1, < 4 s D3), R-06 (normalized audio residency ≤ 50 ms). `docs/test-reports/performance.md` says the Stage 2 thresholds "keep their initial values and are not finalized". |
| Device classes | D1 `iPhone15,4` (reference), D2 `iPad17,3`, D3 `iPad15,7` (`docs/test-reports/devices.md`; `DEVICES` in `scripts/run_device_tests.py`). |
| Measurements | PERF-012 report JSON (`schemaVersion` 1: frame-interval p50/p90/p95/p99/max, PERF-007 drops per output, memory footprint and peak). AutomationRunner `perf001` (1 s frame-rate samples plus PERF-007 drops) and `sc015` (cold-launch seconds list). No report carries audio age today (it exists only as the "Normalized residency" signpost). |
| Verdicts | `run_device_tests.py summarize` hard-codes feature 002's SC-101-SC-104 limits. QA-006's soak has its own verdict. Nothing judges frame rate, frame percentiles, drops, memory, audio age or launch per device class, and no thresholds file exists. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Judge a measurement against the declared budget (Priority: P1)

The owner (or the release checklist) has a performance measurement from a device: an exported performance report,
the automation runner's frame-rate report, the cold-launch samples. They run one check and get, for that device's
class, a pass or fail for every budgeted metric, the limit and the measured value, and the version of the budget
that judged it.

**Why this priority**: it is the roadmap behaviour and its acceptance.

**Independent Test**: fixture reports for each outcome are checked against the committed thresholds; the verdicts
are compared with the expected ones.

**Acceptance Scenarios**:

1. **Given** a D1 report whose figures are all inside D1's budget, **When** checked, **Then** every metric reads
   pass, the overall verdict is pass, and the verdict names the thresholds version.
2. **Given** a report with one figure outside its budget (frame rate, frame percentile, drops, memory or launch),
   **When** checked, **Then** that metric reads fail with value and limit, and the overall verdict is fail.
3. **Given** a report lacking a budgeted metric, **When** checked, **Then** that metric reads "not measured" (never
   pass) and the overall verdict is incomplete, not pass.
4. **Given** a report from a model no class declares, **When** checked, **Then** the check says the device class
   is unknown and judges nothing.
5. **Given** a thresholds file of an unsupported format version, or a version other than the one the caller
   pinned, **When** checked, **Then** the check refuses with that reason and judges nothing.

### User Story 2 - Run the check as part of the final device stage (Priority: P2)

At the final device stage the owner runs the device runner's thresholds step for D1, D2 or D3. It can launch the
existing frame-rate and launch modes, pulls their reports, adds any exported performance report the owner names,
and writes the verdict next to the pulled reports.

**Acceptance Scenarios**:

1. **Given** a dry run, **When** the step runs, **Then** it prints the device commands and judges the files it
   would use, without touching a device.
2. **Given** a simulator run, **Then** the verdict is labelled "not evidence".

### Edge Cases

- Two inputs give the same metric (drops in both the performance report and the automation report): the worse
  value is judged.
- Inputs from two different device models in one check: refused.
- A cold-launch samples file carries no model: the caller names the device.
- A frame-drop count with nothing submitted: not measured.
- A non-numeric or negative value: not measured, with the reason.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-010-R1**: One committed, versioned thresholds file declares the budgets: a format version, a content
  version that changes whenever a limit changes, and the date.
- **QA-010-R2**: It declares device classes keyed by hardware model identifiers: D1, D2, D3, and a simulator/host
  class marked as not evidence.
- **QA-010-R3**: Each class declares targets for: frame rate (5th percentile of 1-second windows), frame-interval
  p50 and p95, dropped-frame share, peak memory, audio age p95 and cold launch; each with its direction (at most /
  at least) and the source criterion it comes from.
- **QA-010-R4**: The thresholds file's shape is documented in a JSON Schema contract; the checker refuses a file
  that does not match its expected format version or structure.
- **QA-010-R5**: The checker reads PERF-012 performance reports, AutomationRunner `perf001` reports and `sc015`
  cold-launch sample lists, alone or together, and judges every metric the device's class declares.
- **QA-010-R6**: Each metric verdict is pass, fail or not measured, with value, limit and source; a metric no input
  provides is not measured, never pass. The overall verdict is fail if any metric fails, otherwise incomplete if
  any is not measured, otherwise pass.
- **QA-010-R7**: Unknown device class, mixed device models, unsupported report or thresholds versions and a
  mismatched pinned thresholds version are errors: nothing is judged and the reason is stated.
- **QA-010-R8**: The verdict is a JSON document (plus a readable text form) carrying the thresholds version, the
  device class, whether it counts as evidence, and the per-metric results; the same inputs always give the same
  bytes.
- **QA-010-R9**: The device runner offers the check as an on-demand step for D1-D3 (and a simulator rehearsal),
  writing the verdict next to the pulled reports; it never runs as part of the normal tests and claims no device
  result by itself.
- **QA-010-R10**: Exit status: 0 for pass, 1 for fail or incomplete, 2 for an error.

### Key Entities

- **Thresholds file**: format version, content version, metric catalogue, device classes.
- **Device class**: identifier, model identifiers, evidence flag, per-metric targets.
- **Metric target**: limit, direction, basis (the criterion it comes from).
- **Verdict**: thresholds version, class, evidence flag, per-metric results, overall result.

## Success Criteria *(mandatory)*

- **QA-010-S1**: 100% of the fixture cases (pass, each kind of fail, missing metric, unknown device class, wrong
  thresholds version) give their expected verdict, and repeated runs give identical output.
- **QA-010-S2**: Every limit in the thresholds file names the criterion or decision it comes from.
- **QA-010-S3**: A budget change is visible as a new content version in every later verdict.
- **QA-010-S4**: On D1, D2 and D3 the final device stage produces a verdict file per device `{device}`.

## Assumptions

- Targets come from existing criteria; where none exists for a class, the decided value is recorded in
  Clarifications.
- Simulator and host results are never evidence (Constitution); their class exists to rehearse the check.
- No app change is needed: the inputs come from existing exports and automation modes.

## Clarifications

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Where do the thresholds live and how are they versioned? → A: `docs/performance/thresholds.json`, with
  `schemaVersion` (the file format, 1; the checker refuses any other) and `thresholdsVersion` (an integer raised by
  one whenever any limit, class or metric changes; 1 now), plus `updated` (date). The contract is
  `docs/performance/thresholds.schema.json`. A caller may pin `--thresholds-version N`; a mismatch is an error.
- Q: Which metrics, and what does each mean? → A: Seven, each with a fixed direction:
  `fps1sP5` (at least): 5th percentile, nearest rank, of 1-second frame-rate windows (AutomationRunner `perf001`
  `fpsTimerOff`), the SC-005 form "95% of 1 s windows ≥ target". `frameIntervalP50Ms`, `frameIntervalP95Ms` (at
  most): PERF-012 `frames.p50Ms`/`p95Ms`. `droppedFramePercent` (at most): PERF-007 device output, 100 × skipped
  ÷ (submitted + skipped), the share of refresh slots that showed no new frame (`skipped` and `submitted` are
  available on every path, projectM included). `peakMemoryMB` (at most): PERF-012
  `resources.memory.peakFootprintBytes` ÷ 1,000,000 (decimal MB, the stricter reading of SC-008). `audioAgeP95Ms`
  (at most): no report carries it today; the checker reads an AutomationRunner report's top-level `audioAgeP95Ms`
  (an additive key a later mode may write), so today it reads "not measured" and a real run's overall verdict is
  incomplete, never pass (declared now so the budget exists). `coldLaunchMs` (at most): the largest `sc015` sample × 1000 (SC-015 counts every launch).
- Q: What are the limits per class? → A: From the existing criteria; where a class had none, the decided value:

  | Metric | D1 `iPhone15,4` | D2 `iPad17,3` | D3 `iPad15,7` | Basis |
  |---|---|---|---|---|
  | `fps1sP5` ≥ | 55 | 55 | 30 | SC-005 (D1); D2 decided same as D1 (60 fps on every preset at Gate 3); D3 = FR-049/SC-013 floor |
  | `frameIntervalP50Ms` ≤ | 18.2 | 18.2 | 33.4 | 1000 ÷ 55 and 1000 ÷ 30 rounded up to the 0.1 ms PERF-012 resolution |
  | `frameIntervalP95Ms` ≤ | 25 | 25 | 50 | PERF-012 long-frame thresholds (1.5 refreshes at 60 Hz; 1.5 at 30) |
  | `droppedFramePercent` ≤ | 5 | 5 | 10 | SC-005's 95%; D3 decided at twice D1's share (oldest tier) |
  | `peakMemoryMB` ≤ | 300 | 300 | 300 | SC-008 (D1); D2, D3 decided at the same budget (they are "measured and published") |
  | `audioAgeP95Ms` ≤ | 50 | 50 | 50 | R-06 normalized residency budget |
  | `coldLaunchMs` ≤ | 2000 | 2000 | 4000 | SC-015; D2 decided same as D1 |

- Q: What about the simulator and the Mac host? → A: A `simulator` class with D1's targets and `evidence: false`.
  It matches the host model identifiers `arm64` and `x86_64`; a simulator reports the simulated model (for example
  `iPhone18,3`), so the device runner passes `--simulator` for simulator runs, which forces this class. Every
  verdict of this class says "not evidence" (Constitution: simulator results are never evidence).
- Q: How are several inputs combined? → A: All inputs of one check must name the same model (a sample list without
  a model takes the caller's `--device`). A metric given by two inputs is judged on its worse value. An unknown
  model is an error ("unknown device class"); the checker never falls back to another class.
- Q: Which language? → A: Python (`scripts/check_performance_thresholds.py`, standard library only): the device
  runner is Python and the inputs are files pulled to the Mac; nothing ships in the app, so no app or package
  change. `scripts/test_scripts.py` covers it with fixture reports in `scripts/fixtures/qa010/`.
- Q: What does "fixture benchmark" mean here? → A: The fixture reports are the benchmark inputs: a committed set
  covering pass, each kind of fail (frame rate, frame percentile, drops, memory, launch), missing metric, unknown
  device class, wrong thresholds version; the checker's verdicts on them are asserted byte for byte deterministic.
- Q: Exit status and output? → A: 0 pass, 1 fail or incomplete, 2 error. The JSON verdict (`kind`
  `projectM-iOS.performanceVerdict`, `verdictSchemaVersion` 1, sorted keys, no timestamps, input file names only,
  never paths) goes to `--out`; stdout prints it with `--json`, otherwise one readable line per metric.
- Q: How is it wired into the device runner? → A: A `thresholds` subcommand of `scripts/run_device_tests.py`:
  `--device D1|D2|D3` or `--simulator <udid>`; `--run` first runs the `perf001` mode and `--repeat` `sc015`
  launches on the target and pulls them; `--report FILE` adds an exported PERF-012 report. It judges the newest
  `automation-perf001-*.json`, `sc015.json` and `performance-*.json` in the target's export folder plus the named
  files, and writes `performance-verdict.json` there. On demand only; not part of `summarize` or any test run.
