# QA-011 device run D1 20261115T195259Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6cdebd3bf89c8116cf3105593957d3b9ca288e32` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:52:59Z, finished 2026-11-15T19:56:03Z
- Summary: pass 3, fail 1
- Record SHA-256: `9a20e5182889fa58d0115ffbce60a7c972c6e7c3e3c46a1a841b6b502c871db0`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 25.4 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T195331Z.json |
| `launches-sc015` | pass | 76.6 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 69.0 | part of QA-010-T12 | report performance-perf012-2026-11-15T195557Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall incomplete |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D1/20261115T195259Z/artifacts/automation-perf001-2026-11-15T195331Z.json` | 1865 | `f884c39e6b55d6285c1d1f98b8a6b4d3c2e0d2aa25779267d37c9133e2ea821a` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D1/20261115T195259Z/artifacts/sc015.json` | 218 | `1b857b29f7e9fa3f6d8c4558029b12dd7fa46a4d7efd7ac0d28f15a0c0bdf035` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D1/20261115T195259Z/artifacts/performance-perf012-2026-11-15T195557Z.json` | 2303 | `1fe9263b94a2fd0d397ee6cffeaa7b8d8831b634703036dcf0afe254ef3c7c22` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D1/20261115T195259Z/artifacts/performance-verdict.json` | 1729 | `cc76533363e8ebe929f36f8c1f892bc6bb052e1b9fe9e74d4d37dc38f6cf6a53` | yes |
