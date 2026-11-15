# QA-011 device run D2 20261115T202300Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `40f13933f5984be504b00e7a68223a76e86ca618`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T20:23:00Z, finished 2026-11-15T20:27:09Z
- Summary: pass 3, fail 1
- Record SHA-256: `d998cc1fe38882fc38e8ffe243996895cb7173edea0fc6421ceffb6b0bceeca8`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 78.5 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T202421Z.json |
| `launches-sc015` | pass | 74.3 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 88.6 | part of QA-010-T12 | report performance-perf012-2026-11-15T202703Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall fail |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261115T202300Z/artifacts/automation-perf001-2026-11-15T202421Z.json` | 3191 | `c335e394c9a8dbfc8cf795a4fb0647cb2fa27b7c24a1664caab8ac4fc584ea0f` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261115T202300Z/artifacts/sc015.json` | 221 | `a07e02a0066a0ce1be0b02eaa557e27f0dcf4af034da83747a4c33a7a9608658` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261115T202300Z/artifacts/performance-perf012-2026-11-15T202703Z.json` | 2526 | `eed90d9a4ceb70537fd44580efbf9b118efac1ad6d79e04df95edac7822af059` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261115T202300Z/artifacts/performance-verdict.json` | 1756 | `92f699a57e1c8e221d576f86fe949c4209e16ab364e44acecd9883bb4579828b` | yes |
