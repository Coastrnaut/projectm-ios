# QA-011 device run D1 20261123T210326Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `b539dacedabffd069038f1507c49a7f50cca1b2a`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-23T21:03:26Z, finished 2026-11-23T21:19:10Z
- Summary: pass 1, fail 2
- Record SHA-256: `370a4df02be7976389e7ea785e74d41e72d9b8d79700f5912e048453c50e8df5`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `rendererlab-flashcost` | fail | 181.4 | part of FX-019-T22 | 28 presets, median 1.37 ms, max 2.64 ms per frame (limit 2.0 ms); over: frontend-uwp/ORB - Mega Spectrum.milk; thermal nominal |
| `xctrace-perf004` | fail | 430.8 | PERF-004-T16 | xctrace did not end by itself and was stopped (perf004: the trace has not changed for 180 s after the recording time); no os-signpost table exported (trace saved: True) |
| `xctrace-perf011` | pass | 274.3 | part of PERF-011-T21 | all pass: 0 frames away, footprint 186.7 -> 160.0 MB, first frame 0.028155922889709473 s after the return |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `rendererlab-flashcost` | `docs/test-reports/qa-011/runs/D1/20261123T210326Z/artifacts/RendererLab-angle-flashcost-2026-11-23T210441Z.json` | 40310 | `c5a70582f178f287bf9b40e35ffad60a3f1027ca3d3e6bad09f895fd783867c6` | yes |
| `xctrace-perf004` | `Build/qa-011/D1/20261123T210326Z/logs/xctrace-perf004-perf004.log` | 354 | `56079683cac67031af3db9d40ca23c37a9a1a57f8332548a7c1ef97d0434071a` | no |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261123T210326Z/artifacts/xctrace-perf004-automation-perf004-2026-11-23T210809Z.json` | 376 | `4aacc9c00ddbd3b0fa4a363c657bf10ea4ca081c9e11ba0b13c8d31cbc23b4c5` | yes |
| `xctrace-perf004` | `docs/test-reports/qa-011/runs/D1/20261123T210326Z/artifacts/xctrace-perf004-verdict.json` | 204 | `87e1150c2fd440c1653637ad8ad08e59870556460266256a17a791ab67c24432` | yes |
| `xctrace-perf011` | `Build/qa-011/D1/20261123T210326Z/logs/xctrace-perf011-perf011.log` | 298 | `50b0a3f28d83df8c973ae7dce3acad181a7890f951a02b73b78b777b71ae4845` | no |
| `xctrace-perf011` | `docs/test-reports/qa-011/runs/D1/20261123T210326Z/artifacts/xctrace-perf011-automation-perf011-2026-11-23T211527Z.json` | 6260 | `f13e576bb362f408e67649ad4047296cf683d696753b67d299050db2b728adc3` | yes |
| `xctrace-perf011` | `docs/test-reports/qa-011/runs/D1/20261123T210326Z/artifacts/xctrace-perf011-verdict.json` | 660 | `fe601cd1acfb668c94d7c8a14a50595be0c6bd88b6a6eba6e7c7625e72aed4d3` | yes |
