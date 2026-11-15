# QA-011 device run D1 20261115T195846Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6cdebd3bf89c8116cf3105593957d3b9ca288e32` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:58:46Z, finished 2026-11-15T20:02:06Z
- Summary: pass 3, fail 1
- Record SHA-256: `524d9fdc80b9c8b00339c0559983bf26d33b091b5c8fddbdaea1eea53143ecfa`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 23.8 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T195915Z.json |
| `launches-sc015` | pass | 76.2 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 88.9 | part of QA-010-T12 | report performance-perf012-2026-11-15T200200Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall fail |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D1/20261115T195846Z/artifacts/automation-perf001-2026-11-15T195915Z.json` | 1875 | `d5a82db12ed2455eb0ed1a2b3ea12a579d1be4da6da6f9443f8e0b8f7efbff92` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D1/20261115T195846Z/artifacts/sc015.json` | 220 | `7a18b9428ea10b63cc1e49ed7ef28770f6570e4095305032f2f95021779d77ec` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D1/20261115T195846Z/artifacts/performance-perf012-2026-11-15T200200Z.json` | 2528 | `dabe7d383fdf0a39a1ddf882cec533351329ef115adc678ebc02035df07355d7` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D1/20261115T195846Z/artifacts/performance-verdict.json` | 1757 | `24f8ee5e6b1879a9b7db97f160e0762fddb5750ead907dbe9c2a6f37e0ef94a4` | yes |
