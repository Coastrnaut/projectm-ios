# QA-011 final physical device matrix: test report

Spec: [specs/313-qa-011-final-device-matrix/](../../specs/313-qa-011-final-device-matrix/spec.md).
Status 2026-11-15: tooling, inventory and owner checklist are done and tested on the Mac. **No device run has
happened yet**; tasks T19-T22 are open and need the owner present with D1-D3. Nothing in this report is device
evidence.

## Inventory (category counts)

`python3 scripts/qa011_inventory.py --check` regenerates [device-inventory.json](qa-011/device-inventory.json)
from every `specs/*/tasks.md` and fails when the committed copy is stale (exit 0 on 2026-11-15).

| Category | Meaning | Tasks |
|---|---|---|
| (a) | scripted: devicectl, on-device XCTest, AutomationRunner; an unlocked device is enough | 14 |
| (b) | a person at the device (music, pickers, purchases, routes, camera, displays, judgement) | 249 |
| (c) | owner-only away from the devices | listed in the checklist |

QA-011's own tasks and waived (⛔) tasks are excluded from the counts; waived ones are listed at the end of the
checklist for completeness.

## Sessions

The 249 category (b) tasks are batched into 13 owner sessions in
[owner-checklist.md](qa-011/owner-checklist.md), each listing devices, preparation, steps and the task IDs it closes:

| Session | Tasks | Session | Tasks |
|---|---|---|---|
| B01 Visuals and effects with music | 36 | B08 Recording | 14 |
| B02 Shows, presets, scenes, controls | 12 | B09 Network, two devices, Airplane Mode | 17 |
| B03 Debug fault injection and recovery | 5 | B10 MIDI hardware | 13 |
| B04 Accessibility | 18 | B11 External display, AirPlay, projector | 31 |
| B05 Audio routes, calls, interruptions | 25 | B12 iPad multitasking | 5 |
| B06 Camera and motion sensors | 21 | B13 Xcode and Instruments measurements | 21 |
| B07 Pickers, iCloud, import and export | 20 | | |

Estimated person time: about 28 h 20 min across the sessions; the scripted matrix runs unattended for about
1-1.5 h per device.

## Commands (main session, owner present)

```bash
python3 scripts/verify_environment.py
python3 scripts/run_device_tests.py build
python3 scripts/run_device_matrix.py --device D1
python3 scripts/run_device_matrix.py verify docs/test-reports/qa-011/runs/D1/<run-id>/record.json
```

Then the same for D2 and D3. Each record carries the device's OS version and build, the app build and commit,
the signing identity and team from `codesign -dv`, every case's status, command and artifacts with SHA-256
hashes, and the record's own hash for QA-012.

## Simulator rehearsal (not evidence)

Own simulator "QA11 iPhone 17", iOS 27.2 (24B8117), Debug build, unsigned; deleted afterwards. The records are
kept locally and gitignored (`docs/test-reports/qa-011/runs/sim/`; CLAUDE.md keeps simulator exports out of git),
so T13's "record committed" is replaced by this summary.

| Case | First run (15:43Z) | Rerun (17:54Z) |
|---|---|---|
| `autorun-perf001` | pass (26.8 s) | — |
| `launches-sc015` | pass (11 launches) | — |
| `warmstart-perf009` | pass (cold 10, warm 11 launches) | — |
| `autorun-sc009` | **fail: no report within 540 s** | reproduced by hand (see below) |
| `thresholds` | fail (expected: QA-010 limits are device numbers) | — |
| `xctest-goldens`, `xctest-soak-600`, `xctest-materials`, `xctest-angle-layer` | pass | — |
| `bench-shd002`, `bench-cmp008`, `bench-cmp009`, `bench-cmp010` | fail: the Compositor test bundle did not compile in Release | **pass** after the fix |
| `bench-expression`, `xctest-offline-export` | pass | — |

Fixes made from the rehearsal:

- Three test files used the DEBUG-only `faultInjection` without a guard, so the Compositor and ANGLERendering test
  bundles could not build in Release (the benches' configuration). They are now `#if DEBUG` (integration commit
  956cfe66); Release builds with testability compile, and the Debug fault tests still pass.
- `--dry-run` created empty run folders (`Target.pull` made its destination before checking for a dry run). A dry
  run now writes nothing.

### Open risk: `autorun-sc009` on the simulator

Launched by hand with `PROJECTM_AUTORUN=sc009`, the app finished its 50 source-switch cycles and then stayed at
"In-App Playback · Interrupted" during the scripted lifecycle (background, foreground, lock, unlock, interruption
began, interruption ended with resume, route lost). No report was written in more than 6 minutes; the process was
alive, its main thread idle and nothing crashed. The simulator logged AVAudioSession error -10879 on every engine
start. The cause is not found. It may be simulator-only, but it may also happen on D1 and D3, so the device run
should watch this case first; AUD-014-T32 stays open either way.

2026-11-18 (QA-011 Batch 2, from the code; not reproduced): the likely cause is a blocking audio call on the main
thread. The stall is right after "interruption began"; the next step's resume runs `AVAudioSession.setActive(true)` and
`AVAudioEngine.start()` synchronously on the main actor, and with the simulator's audio server failing (-10879) such a
call can wait in `mach_msg`, which a sample shows like an idle run loop. sc009 now has a watchdog on its own queue
(`PROJECTM_WATCHDOG`, default 180 s): it writes a partial `automation-sc009` report with the stalled phase, the steps so
far and `mainThreadSilentSeconds`, then exits; sc009 also exits after a complete report. The matrix case
`autorun-sc009` is back as an on-demand case (it needs the microphone answered by the prompt-flow batch), and a
simulator rehearsal samples the app's threads when the report is late.

## Checks (2026-11-15)

- `python3 scripts/test_scripts.py`: 205 tests, OK (1 skipped), including the QA-011 inventory, classifier,
  checklist and record tests.
- `check_compliance.py`, `validate_docs.py` (2680 files), `check_motion_policy.py`, `check_permission_catalog.py`,
  `check_status_events.py`: OK.
- PosterBoard reports: 25 before, 25 after.

## Not verified

- Any run on D1, D2 or D3 (T19-T22), and the signing fields of a real device record.
- The 13 owner sessions.
- The `autorun-sc009` hang described above.
