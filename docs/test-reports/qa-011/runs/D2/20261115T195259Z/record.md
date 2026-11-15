# QA-011 device run D2 20261115T195259Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6cdebd3bf89c8116cf3105593957d3b9ca288e32` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:52:59Z, finished 2026-11-15T19:55:52Z
- Summary: pass 3, fail 1
- Record SHA-256: `5aa61c4c895bc0f47d765725d1e460fcb45c862e3c0fd4c67ebf817970e63b1d`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 23.8 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T195323Z.json |
| `launches-sc015` | pass | 74.8 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 66.8 | part of QA-010-T12 | report performance-perf012-2026-11-15T195547Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall fail |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261115T195259Z/artifacts/automation-perf001-2026-11-15T195323Z.json` | 1839 | `f9aa39de84b3721ccdd43d33bfc6a1c444138f607f3a7aab094cb719998ffe64` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261115T195259Z/artifacts/sc015.json` | 221 | `05c9fb67bc8f02328c8b2167510b1debffd7439c6c0a1c039ab557c019c22923` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261115T195259Z/artifacts/performance-perf012-2026-11-15T195547Z.json` | 2304 | `82c3b492bebdb48756a93c824c4648fdfdd3eda6b6a06b3684d3fab11f9c1cef` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261115T195259Z/artifacts/performance-verdict.json` | 1722 | `0e764260bc3af202df930a100a36b72e4da189d2630844064a287966a284576a` | yes |
