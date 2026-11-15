# QA-011 device run D2 20261115T195808Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6cdebd3bf89c8116cf3105593957d3b9ca288e32` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:58:08Z, finished 2026-11-15T20:01:19Z
- Summary: pass 3, fail 1
- Record SHA-256: `aa19ef6480b75b008b7ec58b63cb03b1854261e02dd8c16fb9bd9da0a1c7387c`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 21.1 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T195830Z.json |
| `launches-sc015` | pass | 77.5 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 86.6 | part of QA-010-T12 | report performance-perf012-2026-11-15T200114Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall fail |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261115T195808Z/artifacts/automation-perf001-2026-11-15T195830Z.json` | 1864 | `3b681f514cab53ea1c1e704aac9651ab55259d1041dde6e7d452faaa6f7b80be` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261115T195808Z/artifacts/sc015.json` | 220 | `e5afe24b7c07af4f7d52c4f20f8cfdd9335e0557ef23e83341df0a64632794ec` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261115T195808Z/artifacts/performance-perf012-2026-11-15T200114Z.json` | 2505 | `6aefbd621c9de6758898ff32a23f9619cb338e8c7ca89ea515cbb6360dfe2d75` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261115T195808Z/artifacts/performance-verdict.json` | 1753 | `e1ee26b264072cd5cb0955170429a0331c28192fbfb430d860b41c8672887580` | yes |
