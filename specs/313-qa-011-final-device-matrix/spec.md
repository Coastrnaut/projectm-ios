# Feature Specification: QA-011 Final physical device matrix

**Feature Branch**: `feature/qa-011` (spec directory `313-qa-011-final-device-matrix`)

**Created**: 2026-11-15

**Status**: Implemented on the Mac 2026-11-15 (tooling, inventory, checklist); device runs T19-T22 open.

**Input**: User description: "Implement QA-011 (Final physical device matrix) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Run complete D1/D2/D3 matrix only after all
implementation tasks close." Acceptance, verbatim: "Signed device run records OS/build, cases, results and
artifacts for each device." P0; depends on QA-001. Test: XCTest, Swift Testing, xcodebuild, xcrun
simctl/devicectl; device FINAL stage."

Identifiers carry the roadmap ID: requirements `QA-011-R1…`, success criteria `QA-011-S1…`, tasks
`QA-011-T01…`. Other features are cited by their own IDs: QA-010 (performance thresholds), QA-006 (render soak),
QA-003 (visual diff goldens), QA-012 (release evidence manifest, the consumer of this feature's records), PERF-001,
PERF-009, AUD-014, SHD-002, SHD-004, SHD-010, CMP-008/009/010, REC-013.

## Baseline: what exists today (audit of 2026-11-15, commit `de5689c2`)

| Area | Today |
|---|---|
| Devices | D1 `iPhone15,4` iOS 27.0.1, D2 `iPad17,3` iPadOS 27.2, D3 `iPad15,7` iPadOS 26.5 (`docs/test-reports/devices.md`); `DEVICES` in `scripts/run_device_tests.py`. |
| Device runner | `scripts/run_device_tests.py`: `devices`, `build` (Release + `PROJECTM_AUTOMATION`), `install`, `perf`, `scroll` (on-device UI test), `entitlement`, `privacy`, `warmstart` (PERF-009), `thresholds` (QA-010), `size`, `summarize`; `--dry-run`, `--simulator <udid>`; a locked device is retried for 30 minutes. Each command handles one feature; nothing runs a whole device pass or records which build, OS and signing produced the results. |
| In-app automation | `AutomationRunner` modes `sc007`, `sc009`, `sc102`, `sc104`, `entitlement`, `privacy`, `perf001`; launch modes `sc015`, `sc101`, `perf009`. Reports land in the app's Documents. |
| On-device XCTest | Package suites and the app's unit tests build for iOS. Environment-gated benches exist (`SHD002_BENCH`, `CMP008_BENCH`, `CMP009_BENCH`, `CMP010_BENCH`, `PARAMETER_EXPRESSION_BENCH`, `QA006_SOAK_SECONDS`); goldens report "pending" on a GPU class without goldens. |
| Open device work | 263 unchecked tasks tagged `{device}` or `{owner}` across 222 `specs/*/tasks.md` (some marked ⛔ not required or optional). They are scattered; nobody has a list of which can be scripted and which need a person, or in what order to do them. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Know exactly what device work is left (Priority: P1)

The owner, before the final device stage, wants one list of every open device or owner task in every feature:
which device(s), which feature, the exact step text, and whether a script can do it, a person must be at the
device, or it is owner-only work away from the device.

**Why this priority**: the matrix and the owner sessions are built from it; without it work is missed.

**Independent Test**: the inventory is regenerated from the task files and compared with the committed copy;
fixture task files with each tag form, waived and optional tasks and multi-line tasks give the expected entries.

**Acceptance Scenarios**:

1. **Given** the task files, **When** the inventory is generated, **Then** every unchecked task line tagged
   `{device}` or `{owner}` appears exactly once with its task ID, feature, devices, category and full step text,
   and format-description lines are not counted.
2. **Given** a task marked "⛔ not required", **Then** it is listed as waived and put in no session.
3. **Given** the committed inventory and a changed task file, **When** the check runs, **Then** it reports the
   inventory as stale.

### User Story 2 - Run every scriptable case on a device with one command (Priority: P1)

At the final device stage, with a device unlocked and Auto-Lock off, the main session runs one command per device.
It builds and installs the measurement build, runs every scriptable case for that device (automation modes,
on-device XCTest suites and benches, the QA-010 threshold judge), collects the artifacts and writes a signed run
record.

**Why this priority**: it is the roadmap acceptance.

**Independent Test**: a dry run prints every command for D1, D2 and D3 without touching a device; a full rehearsal
on a dedicated simulator produces a record marked "simulator rehearsal, not evidence".

**Acceptance Scenarios**:

1. **Given** a connected, unlocked device, **When** the matrix runs, **Then** the record names the device model,
   OS version and build, the app version, build number and commit, the signing identity and team that the code
   signature reports, each case with its result, duration, command and the tasks it closes, and every artifact with
   its SHA-256 hash; the record's own hash is stored beside it.
2. **Given** a device that stays locked, **When** a case needs it, **Then** the runner retries for the configured
   time, then stops that device with a clear "unlock it and set Auto-Lock to Never" message, records the case as
   blocked and the remaining cases as not run.
3. **Given** a device that is not listed or is unavailable, **Then** the record says so and no case runs.
4. **Given** a case that exceeds its time limit, **Then** it is recorded as timed out and the next case runs.
5. **Given** `--simulator <udid>`, **Then** every record and summary says "simulator rehearsal, not evidence".

### User Story 3 - Do the human steps in a few batched sessions (Priority: P2)

The owner wants the person-only steps grouped into a small number of sessions, ordered so the app is reinstalled
and hardware is changed as rarely as possible, each with its device, preparation, actions, what to record and the
task IDs it closes.

**Why this priority**: the remaining device work is mostly human; batching makes it feasible.

**Independent Test**: every category (b) task of the inventory appears in exactly one session of the generated
checklist.

**Acceptance Scenarios**:

1. **Given** the inventory, **When** the checklist is generated, **Then** each session lists device(s),
   preparation, the steps (exact task text), what to record and the closed task IDs, with an estimated duration.
2. **Given** a task that a script can partly do, **Then** the checklist names the matrix case that covers the
   scripted part.

### Edge Cases

- A task tag inside back-quotes (`` `{device}` ``) counts like a bare tag.
- A task whose text spans several indented lines is one task.
- A task naming no device is assigned to D1 (the reference device) and marked as inferred.
- "D1-D3", "D1–D3", "D1/D2", "every device", "an iPad" and "iPadOS 26.5" map to the right devices.
- A case that closes a task on D1 only is not run on D2 or D3.
- The app-hosted XCTest suite replaces the measurement build, so it runs after the automation cases.
- An artifact that is a folder (an `.xcresult`) gets one hash over its sorted file list and contents.
- No previous run exists for a dry run: nothing is written.
- QA-011's own `{device}` tasks (the device runs) are not listed in the inventory they are built from.
- A fresh install resets the microphone permission: the `sc009` case needs one Allow tap on D1 and D3 (the
  runner prints when; a rehearsal grants it with `simctl privacy`).

## Requirements *(mandatory)*

### Functional Requirements

- **QA-011-R1**: A generator reads every `specs/*/tasks.md` and lists each unchecked task tagged `{device}` or
  `{owner}`: task ID, spec directory, feature ID, devices (D1/D2/D3, with an "inferred" flag), status (open,
  optional, waived), category, session, the full step text, and the matrix cases that cover it.
- **QA-011-R2**: Categories: (a) scriptable with only an unlocked device and Auto-Lock off; (b) needs a person at
  the device (purchase sheets, system pickers, Airplane Mode, permission prompts, external display or projector,
  headphones and calls, MIDI hardware, visual or listening judgement, music playback, Instruments); (c) owner-only
  work away from devices (App Store Connect, signing). The rules are explicit and tested.
- **QA-011-R3**: The inventory is committed as JSON with counts per category, per device and per session; a check
  mode fails when the committed file differs from a fresh generation.
- **QA-011-R4**: Category (b) tasks are grouped into a small fixed set of owner sessions (at most 13) in an order
  that minimises reinstalls and hardware changes; each session has preparation, recording notes and an estimated
  duration.
- **QA-011-R5**: An owner checklist is generated from the inventory: per session the device(s), preparation, the
  exact steps with their task IDs, what to record and the tasks it closes.
- **QA-011-R6**: A matrix runner runs, per device, every category (a) case assigned to that device: AutomationRunner
  modes, launch modes, on-device XCTest suites and benches, and the QA-010 threshold judge, in an order that needs
  one install of the measurement build.
- **QA-011-R7**: Each device run writes a record (JSON and a Markdown summary) with: device model, name, OS version
  and build; app version, build number, commit SHA and whether the tree was dirty; the code signature's authority
  (signing identity) and team; host Xcode version; start and end times; per case the status (pass, fail, timeout,
  blocked, error, skipped, not run), duration, command, tasks closed and artifacts; each artifact's path, size and
  SHA-256; and the SHA-256 of the record itself (stored in the record and a sidecar file).
- **QA-011-R8**: A locked device is retried for a configurable time (default 10 minutes), then that device stops
  with a clear message; an unlisted or unavailable device is recorded and skipped; each case has a time limit.
- **QA-011-R9**: `--dry-run` prints every command without running any and writes nothing; `--simulator <udid>`
  rehearses on a simulator and labels everything "simulator rehearsal, not evidence".
- **QA-011-R10**: The runner never changes signing: it uses the team the project already resolves (the gitignored
  local signing file) and records what the signature reports.
- **QA-011-R11**: The matrix is reachable as `run_device_tests.py matrix` as well as its own script.
- **QA-011-R12**: The device runs themselves stay open tasks for the owner's final device stage; no device result
  is claimed by this feature.

### Key Entities

- **Inventory entry**: task ID, spec, feature, devices, status, category, session, step text, matrix cases.
- **Owner session**: ID, title, devices, preparation, recording notes, order, tasks, estimated minutes.
- **Matrix case**: ID, kind (autorun, launches, warmstart, xctest, thresholds), devices, command, time limit,
  tasks closed.
- **Run record**: target, app, signing, host, cases, artifacts, summary, record hash, evidence flag.

## Success Criteria *(mandatory)*

- **QA-011-S1**: 100% of the open `{device}`/`{owner}` tasks appear exactly once in the inventory, and 100% of the
  category (b) tasks appear in exactly one owner session.
- **QA-011-S2**: The dry run lists every category (a) case for each of D1, D2 and D3 without contacting a device.
- **QA-011-S3**: A simulator rehearsal runs every case and writes a record whose artifact hashes all verify, marked
  as not evidence.
- **QA-011-S4**: On each of D1, D2 and D3 the final device stage produces a signed run record with OS/build, cases,
  results and artifacts `{device}`.
- **QA-011-S5**: The owner's person-only work fits in at most 13 sessions.

## Assumptions

- QA-001's gate (all implementation rows integrated) is met: integration commit `de5689c2` reports every
  implementation row integrated.
- Simulator and host results are never evidence (Constitution X).
- Package suites run on a device through `xcodebuild test` with the owner's existing local signing configuration;
  the app's unit-test bundle is hosted in the app.
- No app code change is needed.

## Clarifications

### Owner ruling 2026-11-15 (device stage)

- Records are public, so a record's signing section keeps only the certificate type ("Apple Development") and the
  team ID; the certificate holder's name and personal certificate ID are withheld (`redact_signing`). Paths inside
  the repository are written relative to it. The seven records written before the ruling were rewritten this way
  (new record hashes; each says so in `signing.redaction`).
- Package suites run on a device hosted in the signed app (`DeviceTests.yml`): Xcode refuses tool-hosted package
  tests on device destinations. ANGLE's layer tests have no device host yet and are recorded "not-run".

### Session 2026-11-15 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: How is a task classified, and what happens to a task a script can only partly do? → A: Explicit, tested
  rules in `scripts/qa011_inventory.py`: (1) an explicit table of category (a) task IDs, each mapped to the matrix
  cases that fully close it (a task is (a) only when every part of it is scripted); (2) (c) when the text names
  App Store Connect, signing, certificates, profiles or TestFlight and no device step; (3) everything else is (b),
  assigned to the first session whose keyword rule matches (ordered by hardware). A (b) task whose scriptable part
  is covered by a matrix case lists that case under `matrixCases` ("automated part"), and the checklist says so.
  Status: `waived` when the text carries "⛔"; `optional` when it says optional, "only if a later row needs it" or
  "not required for this row"; otherwise `open`. Waived tasks are listed but put in no session; optional tasks are
  put in a session and marked optional.
- Q: Which devices does a task get when its text is vague? → A: Explicit device mentions win: "D1-D3"/"D1–D3"/
  "every device"/"each device" → all three; "D1/D2", "D1 and D3" etc. → those; "iPadOS 26.5" or "iOS 26" → D3;
  "an iPad"/"the iPads" without a D-number → D2 and D3; "reference device" → D1. A task naming none gets D1 (the
  reference device) with `devicesInferred: true`.
- Q: Where do inventory, records and artifacts live, and what is committed? → A: Committed: the inventory
  `docs/test-reports/qa-011/device-inventory.json`, the owner checklist `docs/test-reports/qa-011/owner-checklist.md`,
  run records `docs/test-reports/qa-011/runs/<D1|D2|D3|sim>/<run-id>/record.json` with `record.md` and
  `record.json.sha256`, and the small JSON reports pulled from the app (same folder, `artifacts/`). Not committed:
  `.xcresult` bundles and xcodebuild logs, kept under `Build/qa-011/<label>/<run-id>/` (gitignored, `--work-dir`
  to override); the record holds their paths, sizes and hashes so QA-012 can cite them. A folder artifact is hashed
  as SHA-256 over its sorted `relative-path NUL file-SHA-256 LF` lines. The record hash is the SHA-256 of the
  record's canonical JSON (sorted keys, no `recordSha256` field), stored in the record and the sidecar.
- Q: How do package test suites run on a device without changing signing? → A: `xcodebuild test` in the
  package folder with `-destination 'platform=iOS,id=<hardware UDID>' -allowProvisioningUpdates -xcconfig
  Configs/Signing.xcconfig`: the committed file only includes the owner's gitignored local file, so the team comes
  from the owner's configuration and nothing is written. The app-hosted suite uses the project's own configuration.
  The run record carries `codesign -dv` of the installed measurement build (Authority = signing identity,
  TeamIdentifier = team); a simulator rehearsal records "not signed" or "ad hoc" exactly as codesign reports it.
- Q: How long is a locked device waited for, and what are the case time limits? → A: `--locked-wait` default
  600 s (retry every 15 s), then that device stops: the case is `blocked`, later cases `not-run`, and the message
  says "unlock <D> and set Auto-Lock to Never, then rerun with --only <remaining cases>". Each case has its own
  limit (automation modes 2-10 minutes, XCTest suites 10 minutes, the 600 s simulated soak 20 minutes); a case over
  its limit is `timeout` and the run continues. A device not listed by devicectl, or listed with tunnel state
  `unavailable`, is recorded `unavailable` with no case run.
- Q: Which cases form the matrix? → A: In order (one install of the measurement build, app-hosted XCTest last
  because it replaces the app): `autorun-perf001`, `launches-sc015`, `warmstart-perf009`, `autorun-sc009`,
  `thresholds` (QA-010 judge over the pulled reports plus any PERF-012 export given with `--perf012-report`),
  package XCTest `xctest-goldens` (RenderGoldens), `xctest-soak-600` (`QA006_SOAK_SECONDS=600`),
  `xctest-materials` (Compositor ProceduralMaterialsTests), `xctest-angle-layer` (ProjectMLayerTests,
  ClientBufferSpikeTests), the benches `bench-shd002`, `bench-cmp008`, `bench-cmp009`, `bench-cmp010`,
  `bench-expression`, and the app-hosted `xctest-offline-export` (REC-013). Each case runs only on the devices of
  the tasks it closes.
- Q: How many owner sessions, and in what order? → A: Thirteen, ordered so that no-extra-hardware sessions on one
  Debug install come first and hardware is added one kind at a time: B01 visuals and effects, B02 shows/presets/
  scenes/ergonomics, B03 Debug fault injection, B04 accessibility, B05 audio routes and calls, B06 camera and
  sensors, B07 pickers, files and sharing, B08 recording, B09 network and Airplane Mode (starts with a fresh
  install), B10 MIDI hardware, B11 external display, AirPlay and projector, B12 iPad multitasking, then B13
  Xcode/Instruments-attached measurements last (a Release build attached to Xcode). Including the
  Instruments session, which revises QA-011-S5 to "at most 13 sessions". Estimated duration: 5 minutes per task
  and device, plus any duration named in the step (for example "5 min"), rounded up to 5 minutes per session.
- Q: Does this feature run anything on D1-D3? → A: No. Agents never touch the devices (owner rule; CLAUDE.md).
  The device runs are open tasks `{device}` for the owner's final device stage, driven by the main session; only
  the dry run and a simulator rehearsal (marked not evidence) are run here.

### Session 2026-11-15 (speckit-analyze)

- Q: Is AUD-014-T32 (`sc009`) still category (a) when the fresh install asks for the microphone? → A: Yes, with
  one documented tap: the run must start from an empty container (otherwise `sc015.json` and `perf009.json` would
  mix earlier samples), so iOS asks once for microphone access during `autorun-sc009`; the runner prints when, the
  case waits up to 540 s, and the checklist's Session 0 says to stay at D1 and D3 for it. Nothing else in the
  matrix needs a person.
- Q: Does the inventory list QA-011's own device-run tasks? → A: No; they are the matrix itself (excluded by the
  spec directory name).
