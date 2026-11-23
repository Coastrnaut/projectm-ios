# QA-011 device run D2 20261123T165657Z

- Target: device iPad77 `iPad17,3`, OS 27.2.1 (24B156), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6133a88a5a8911df1d467d277268e4f96287c609`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-23T16:56:57Z, finished 2026-11-23T17:02:23Z
- Summary: pass 6
- Record SHA-256: `bfc8f63101a73dd13c3ce86606d53a8e0e62810b3c49dc01bc210fc0af7196fe`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 79.8 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-23T165816Z.json |
| `launches-sc015` | pass | 76.9 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 86.5 | part of QA-010-T12 | report performance-perf012-2026-11-23T170103Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-angle-layer` | pass | 58.5 | part of CMP-001-T20 | 9 tests, 0 failures, 0 skipped; 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set |
| `xctest-pre012-limits` | pass | 16.6 | part of PRE-012-T31 | 2 tests, 0 failures, 0 skipped |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261123T165657Z/artifacts/automation-perf001-2026-11-23T165816Z.json` | 3173 | `ce9ba946648cc386f790f999be73a0284af7b37f3a14c64bff324de737f52106` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261123T165657Z/artifacts/sc015.json` | 220 | `115fe5a704e6b1467ead3e234f38b66a254ee99017cc9feb1a918d2cf6d7da3e` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261123T165657Z/artifacts/performance-perf012-2026-11-23T170103Z.json` | 2478 | `6c7584f915501ef8e3996815a13e45604e85707fc9393a9e8634a8fd5d4fe40a` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261123T165657Z/artifacts/performance-verdict.json` | 1758 | `47f3041d3c88ac8dd907008c458d2f591dc9d3b2abe98c43d9616e405c9cbec4` | yes |
| `xctest-angle-layer` | `Build/qa-011/D2/20261123T165657Z/logs/xctest-angle-layer.log` | 3640957 | `d36bba217cc52d8044675ceed202be73dd4b43755607edc7c8e61cde480b8797` | no |
| `xctest-angle-layer` | `Build/qa-011/D2/20261123T165657Z/xcresult/xctest-angle-layer.xcresult` | 425775 | `ec2021e0833423fbaf7095f427abb6d79e66296640e7ebf9eff0777d51887af8` | no |
| `xctest-pre012-limits` | `Build/qa-011/D2/20261123T165657Z/logs/xctest-pre012-limits.log` | 406102 | `1fd88fb6b148167c397b537966cbf833e57e53ce07b7203fd67d8f5269a87774` | no |
| `xctest-pre012-limits` | `Build/qa-011/D2/20261123T165657Z/xcresult/xctest-pre012-limits.xcresult` | 50317 | `a1ee1a2a8b2053c03edcff4813b87bc8106900bb4f62279da8a3aac16ab0d535` | no |
