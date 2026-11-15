# Tasks: QA-011 Final physical device matrix

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/run-record.md](contracts/run-record.md), [quickstart.md](quickstart.md)

Format: `- [ ] QA-011-Tnn [P?] [Story?] Description (file)`. `{device}` = needs D1-D3 and the owner present
(left open). Budgets (owner rule 7): each unit test ≤ 10 s; the script suite as before.

## Phase 1: Setup

- [ ] QA-011-T01 Fixture task files covering every tag form (bare, back-quoted, `{A}{device}`), a waived (⛔) task,
  an optional task, a multi-line task, a checked task, a format-description line and an `{owner}` App Store
  Connect task, plus a trimmed devicectl listing (`scripts/fixtures/qa011/`)

## Phase 2: Foundational

- [ ] QA-011-T02 Task parser: unchecked `- [ ] ` lines with indented continuations joined, tag detection,
  task ID, spec and feature from the directory name (`scripts/qa011_inventory.py`)

## Phase 3: User Story 1 - Know exactly what device work is left (P1)

- [ ] QA-011-T03 [US1] Device inference ("D1-D3", "D1–D3", "D1/D2", "D1 and D3", "every device", "iPadOS 26.5",
  "an iPad", "reference device"; none → D1 with `devicesInferred: true`) and status (`open`, `optional`,
  `waived`) (`scripts/qa011_inventory.py`)
- [ ] QA-011-T04 [US1] Classifier: explicit category (a) table mapped to matrix case IDs, (c) owner-only rule,
  ordered keyword session rules for (b), automated-part links (`scripts/qa011_inventory.py`)
- [ ] QA-011-T05 [US1] Inventory writer (`kind` `projectM-iOS.qa011.deviceInventory`, `schemaVersion` 1, sorted,
  no timestamps), counts per category/status/device/session, and `--check` (exit 1 when stale)
  (`scripts/qa011_inventory.py`, `docs/test-reports/qa-011/device-inventory.json`)
- [ ] QA-011-T06 [US1] Tests: parser on the fixtures (count, multi-line, format lines excluded, checked excluded),
  devices, status, classifier, determinism, `--check` stale detection (`scripts/test_scripts.py`
  `QA011InventoryTests`)

## Phase 4: User Story 2 - Run every scriptable case on a device with one command (P1)

- [ ] QA-011-T07 [US2] Matrix case catalogue (ids, kinds, devices from the tasks they close, time limits, order:
  autorun → launches → warmstart → thresholds → package XCTest → benches → app-hosted XCTest) shared with the
  inventory (`scripts/run_device_matrix.py`)
- [ ] QA-011-T08 [US2] Target info (devicectl listing → model, OS version, build, UDID, tunnel state; simctl for a
  simulator), app info (Info.plist version/build, git commit and dirty flag), codesign parsing
  (`scripts/run_device_matrix.py`)
- [ ] QA-011-T09 [US2] Case runners reusing `run_device_tests.Target`: autorun and launch modes with report pulls,
  warmstart, QA-010 judge, `xcodebuild test` for package and app suites (`-allowProvisioningUpdates`, `-xcconfig
  Configs/Signing.xcconfig` for packages, `TEST_RUNNER_` environment, result bundle per case), locked retry with
  `--locked-wait`, per-case timeouts, unavailable devices (`scripts/run_device_matrix.py`)
- [ ] QA-011-T10 [US2] Record writer: artifact hashing (files and folders), canonical JSON, `recordSha256` and
  sidecar, Markdown summary, `verify` subcommand; `--dry-run` writes nothing (`scripts/run_device_matrix.py`)
- [ ] QA-011-T11 [US2] `matrix` passthrough in `scripts/run_device_tests.py`
- [ ] QA-011-T12 [US2] Tests: dry-run command plan per device (D1 runs perf001 and the soak, D2 not the soak, D3
  sc009 but not bench-cmp008), lock detection, codesign parsing (signed, ad hoc, unsigned), folder hash stability,
  record hash round trip and tamper detection, devicectl listing parsing (`scripts/test_scripts.py`
  `QA011MatrixTests`)
- [ ] QA-011-T13 [US2] Simulator rehearsal on an own `QA11 iPhone 17` (iOS 27.2) simulator, deleted afterwards;
  record committed under `docs/test-reports/qa-011/runs/sim/` and marked not evidence; PosterBoard reports counted
  before and after (`docs/test-reports/final-device-matrix.md`)

## Phase 5: User Story 3 - Do the human steps in a few batched sessions (P2)

- [ ] QA-011-T14 [US3] Session catalogue B01-B13 (title, install, preparation, what to record, order) and
  duration estimate (`scripts/qa011_inventory.py`)
- [ ] QA-011-T15 [US3] Owner checklist generator: matrix commands per device first, then each session with its
  devices, preparation, steps (task ID, devices, exact text, automated part), what to record and closed IDs;
  waived tasks listed at the end (`docs/test-reports/qa-011/owner-checklist.md`)
- [ ] QA-011-T16 [US3] Tests: every (b) task in exactly one session, ≤ 13 sessions, every session's tasks appear in
  the checklist (`scripts/test_scripts.py`)

## Phase 6: Polish

- [ ] QA-011-T17 Test report (`docs/test-reports/final-device-matrix.md`): counts, sessions, commands, rehearsal
  output, what is not verified; spec Status line
- [ ] QA-011-T18 Repo checks: `test_scripts.py`, `check_compliance.py`, `validate_docs.py`,
  `check_motion_policy.py`, `check_permission_catalog.py`, `check_status_events.py`

## Phase 7: Final device stage (owner present) `{device}`

- [ ] QA-011-T19 {device} D1: `run_device_tests.py build`, then `run_device_matrix.py --device D1`; commit the
  record and `verify` it (QA-011-S4)
- [ ] QA-011-T20 {device} D2: `run_device_matrix.py --device D2`; commit and verify the record (QA-011-S4)
- [ ] QA-011-T21 {device} D3 (iPadOS 26.5): `run_device_matrix.py --device D3`; commit and verify the record
  (QA-011-S4)
- [ ] QA-011-T22 {device} The owner sessions B01-B13 of `owner-checklist.md`; each closes its listed tasks in
  their own features

## Dependencies

T01 → T02 → T03-T05 → T06. T07 depends on T04 (shared case IDs). T08-T10 → T11 → T12 → T13. T14 → T15 → T16.
T17-T18 last. T19-T22 need the owner and run after QA-001's gate (all implementation rows integrated).

## Parallel opportunities

T06 and T12 test different modules; T14 can be written alongside T08-T10.

## Implementation strategy

MVP = US1 (the inventory), then US2 (runner, rehearsal), then US3 (checklist).
