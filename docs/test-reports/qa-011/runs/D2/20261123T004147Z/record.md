# QA-011 device run D2 20261123T004147Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `c13a5dc50b23ec1d82425e03ac4f4fdbadf520e7`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-23T00:41:47Z, finished 2026-11-23T00:49:33Z
- Summary: pass 6
- Record SHA-256: `d35c41d50532ab8a60659330186829005b6c3079e3b6e89a0eb4633154a5541d`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 77.3 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-23T004524Z.json |
| `launches-sc015` | pass | 74.2 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 88.1 | part of QA-010-T12 | report performance-perf012-2026-11-23T004805Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-angle-layer` | pass | 66.6 | part of CMP-001-T20 | 9 tests, 0 failures, 0 skipped; 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set |
| `xctest-pre012-limits` | pass | 14.2 | part of PRE-012-T31 | 2 tests, 0 failures, 0 skipped |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261123T004147Z/artifacts/automation-perf001-2026-11-23T004524Z.json` | 3182 | `a4eb5c3b2ff5047d6ebf05e86f48b1cbf0c93cec90327d1ba9abb335a8c63363` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261123T004147Z/artifacts/sc015.json` | 219 | `784fe95378dacf4134618f36aed9b6f0afee7c845ca8beea5ac1008a453a2de5` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261123T004147Z/artifacts/performance-perf012-2026-11-23T004805Z.json` | 2503 | `4b9d0b9b8f2664d6bf3e08e1de2b9cf0c1e41995767a98082826d78e8d1235d7` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261123T004147Z/artifacts/performance-verdict.json` | 1755 | `5b5493415753062105f788aefebcb5b1fb013e794ae846f225d0f48edcf7a42e` | yes |
| `xctest-angle-layer` | `Build/qa-011/D2/20261123T004147Z/logs/xctest-angle-layer.log` | 3640589 | `b91df6b22f9cfa7b69229bf8d7f21a938e6fa9e20e9931510337c1c465b22aaa` | no |
| `xctest-angle-layer` | `Build/qa-011/D2/20261123T004147Z/xcresult/xctest-angle-layer.xcresult` | 429105 | `cc1ea21ed91f8ebab13cf87f045e1b12c23d2e956750e6dcc8fe45faefb9fbd0` | no |
| `xctest-pre012-limits` | `Build/qa-011/D2/20261123T004147Z/logs/xctest-pre012-limits.log` | 406095 | `2a6b0918799ca0776df630d4f6207c87ea7c1b005eec42290c2fa52cef2a55ae` | no |
| `xctest-pre012-limits` | `Build/qa-011/D2/20261123T004147Z/xcresult/xctest-pre012-limits.xcresult` | 50509 | `10b968b213b830730cd4a2ba800bd7ef121ac93f40320ad890ab4e5178a26cb1` | no |
