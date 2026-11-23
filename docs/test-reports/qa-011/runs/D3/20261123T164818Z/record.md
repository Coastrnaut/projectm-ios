# QA-011 device run D3 20261123T164818Z

- Target: device iPadC `iPad15,7`, OS 26.5 (23F77), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6133a88a5a8911df1d467d277268e4f96287c609`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-23T16:48:18Z, finished 2026-11-23T16:56:57Z
- Summary: pass 6, fail 1
- Record SHA-256: `7ab54e2b12a7dc9ceb2c8eafe6b44d386eeaadc01673d5874126d753a401cf56`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 79.4 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-23T165043Z.json |
| `launches-sc015` | pass | 73.2 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 85.4 | part of QA-010-T12 | report performance-perf012-2026-11-23T165324Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-angle-layer` | pass | 68.4 | part of CMP-001-T20 | 9 tests, 0 failures, 0 skipped; 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set |
| `xctest-pre012-limits` | pass | 16.9 | part of PRE-012-T31 | 2 tests, 0 failures, 0 skipped |
| `bench-rec003-encoder` | fail | 123.0 | part of REC-003-T23 | no test summary in the log; exit 65; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D3/20261123T164818Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH= |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D3/20261123T164818Z/artifacts/automation-perf001-2026-11-23T165043Z.json` | 3184 | `8be542a5e60cefddb6c903349c10ab32c427555c59aea6860999de40b25194bb` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D3/20261123T164818Z/artifacts/sc015.json` | 220 | `9ff5394721f5ec45911f3cf4e9395b05fda01debb2565a5379ea76be2ae11d09` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D3/20261123T164818Z/artifacts/performance-perf012-2026-11-23T165324Z.json` | 2491 | `158db080afe11a987261c9e30905523c9baaeeaa7077ccab556f80931fecc34f` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D3/20261123T164818Z/artifacts/performance-verdict.json` | 1759 | `967183d345f241a817123a660e1e08c4850a7705c6057f4b6b668af2fd8c1c70` | yes |
| `xctest-angle-layer` | `Build/qa-011/D3/20261123T164818Z/logs/xctest-angle-layer.log` | 3639883 | `c2c45f6925ab1e3450f63a462ffb64a82c3102fbfb8eb93d777a1028fb019f5a` | no |
| `xctest-angle-layer` | `Build/qa-011/D3/20261123T164818Z/xcresult/xctest-angle-layer.xcresult` | 431235 | `9163b677ea15a816abb5689bfcdab1358d601251a3daa08f1e0ee0d7ef11c662` | no |
| `xctest-pre012-limits` | `Build/qa-011/D3/20261123T164818Z/logs/xctest-pre012-limits.log` | 405039 | `000779fd25ef1f8205c38f6fede75929d511ee98a0b4082bfdcb86300b2ea062` | no |
| `xctest-pre012-limits` | `Build/qa-011/D3/20261123T164818Z/xcresult/xctest-pre012-limits.xcresult` | 49587 | `c6e0b61ac7bde08fec296d075f8676c0f44d907cf16dc45b94d86bb1d8bc9ecf` | no |
| `bench-rec003-encoder` | `Build/qa-011/D3/20261123T164818Z/logs/bench-rec003-encoder.log` | 3679759 | `30bc5e59ceddccaae581cbf949530df462a034ada1db6682fe1fd257640ee7ea` | no |
| `bench-rec003-encoder` | `Build/qa-011/D3/20261123T164818Z/xcresult/bench-rec003-encoder.xcresult` | 273726 | `668a94f74dd778f83a0d9ff2e2e5fdede389ba2591bde29efa310cdb921d9fc4` | no |
