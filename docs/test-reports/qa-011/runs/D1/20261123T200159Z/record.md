# QA-011 device run D1 20261123T200159Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `3c11fc11083f037b68b5e5852a93ba0691817b51`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-23T20:01:59Z, finished 2026-11-23T20:23:58Z
- Summary: fail 3
- Record SHA-256: `569c7c7f5ba78c6fcfafc67133ce975c3894b291020cc83a275108b50e4b7fc1`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `rendererlab-flashcost` | fail | 168.2 | part of FX-019-T22 | 28 presets, median 1.66 ms, max 2.99 ms per frame (limit 2.0 ms); over: frontend-uwp/EoS - dark side of the moon (plus a few more hits and a pill).milk, frontend-uwp/EoS+Phat - Arm_upgrades - transformer.milk, frontend-uwp/Fvese - Snowflake Like 2.milk, frontend-uwp/Geiss - Mega Swirl 3.milk, fronte |
| `xctrace-perf004` | fail | 373.4 | PERF-004-T16 | 42 allocations: 0 at start, 28 at size changes, 14 elsewhere (at [8.911, 8.911, 8.911, 8.911, 8.911] s) |
| `xctrace-perf011` | fail | 695.2 | part of PERF-011-T21 | the app was not backgrounded and brought back during the run; GPU intervals not checked (no metal-gpu-intervals table exported) |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `rendererlab-flashcost` | `docs/test-reports/qa-011/runs/D1/20261123T200159Z/artifacts/RendererLab-angle-flashcost-2026-11-23T200319Z.json` | 40313 | `494071a06adae463f84380bc39ff9659367b000d89025e0da868ea034f147df2` | yes |
| `xctrace-perf004` | `Build/qa-011/D1/20261123T200159Z/logs/xctrace-perf004-perf004.log` | 260 | `961302523de875e89f55e50cdea8e2aab389c6ba960a082aa88090834775fa52` | no |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261123T200159Z/artifacts/xctrace-perf004-automation-perf004-2026-11-23T200643Z.json` | 376 | `6510ca381a65634f57cb941b0eb0d02aebf47d4984dccb24aff5ea336bfb59ea` | yes |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261123T200159Z/artifacts/xctrace-perf004-verdict.json` | 500 | `1c65248fb3dd429b8ced77351a030a9e5d7af2fa5388dceff69d00c1f2695784` | yes |
| `xctrace-perf011` | `Build/qa-011/D1/20261123T200159Z/logs/xctrace-perf011-perf011.log` | 241 | `5c91ea38bea8aac855e08c72d7ccd4bf0c1962a934d6d50923729c1663e0dff8` | no |
| `xctrace-perf011` | `docs/test-reports/qa-011/runs/D1/20261123T200159Z/artifacts/xctrace-perf011-automation-perf011-2026-11-23T201346Z.json` | 7643 | `48fe1e480eb1580799ac28a2243122b8ec596639ff2aaf41efe49925733db852` | yes |
| `xctrace-perf011` | `docs/test-reports/qa-011/runs/D1/20261123T200159Z/artifacts/xctrace-perf011-verdict.json` | 248 | `22b478bbe0bf4dafca04b850a5c4e8804da4c93fd9b7eb6f054385a83a4f7b4d` | yes |
