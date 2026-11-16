# QA-011 device run D3 20261116T032055Z

- Target: device iPadC `iPad15,7`, OS 26.5 (23F77), state disconnected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `da085580a3c08f740ababc4a040ed6129b0ee214` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-16T03:20:55Z, finished 2026-11-16T03:29:01Z
- Summary: pass 7
- Record SHA-256: `a0104fee4532a020d1d9cc4acacaa1dab4f9d5516a013c23145ba2fb30cede58`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 81.9 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-16T032220Z.json |
| `launches-sc015` | pass | 76.1 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 86.3 | part of QA-010-T12 | report performance-perf012-2026-11-16T032506Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-materials` | pass | 66.1 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped |
| `xctest-angle-layer` | pass | 17.0 | part of CMP-001-T20 | 7 tests, 0 failures, 0 skipped |
| `bench-shd002` | pass | 145.8 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D3/20261116T032055Z/xcresult/bench-shd002.xcresult / SHD002_BENCH device Apple A16 GPU: 12-node graph median 10.994749998644693 ms,  |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D3/20261116T032055Z/artifacts/automation-perf001-2026-11-16T032220Z.json` | 3185 | `fe608a04018a2ae98811664ceb4223569900e500ed2c63d9ab99a2deeaf70955` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D3/20261116T032055Z/artifacts/sc015.json` | 219 | `85ac733048bf5b4bc20d91aa0d4d2e4c05ed64fbc1aa33249222929456910c4d` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D3/20261116T032055Z/artifacts/performance-perf012-2026-11-16T032506Z.json` | 2508 | `d3c9691330c077791b3455b1831caf0be8bed765a29947cf08b3758e6cf35b54` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D3/20261116T032055Z/artifacts/performance-verdict.json` | 1756 | `cd4d4192b4f75010bd77eb79c2056646d7e2172fe4fe802132409da516a3d7da` | yes |
| `xctest-materials` | `Build/qa-011/D3/20261116T032055Z/logs/xctest-materials.log` | 3372541 | `ff084753a396a5470b866f6ac62af429c36f252032ee0b02609fe00672a01b74` | no |
| `xctest-materials` | `Build/qa-011/D3/20261116T032055Z/xcresult/xctest-materials.xcresult` | 398974 | `dc910092998ea0dc8ef338322da81cdc786b5e260fb8913481a70a6f7314a31f` | no |
| `xctest-angle-layer` | `Build/qa-011/D3/20261116T032055Z/logs/xctest-angle-layer.log` | 294115 | `d553e835d1e398223886b28ad4bfb78586ba2824a9365bc026f833785ef6ec4a` | no |
| `xctest-angle-layer` | `Build/qa-011/D3/20261116T032055Z/xcresult/xctest-angle-layer.xcresult` | 53177 | `b3b5d3f1feb5575ec5c6f458c1f161418954af95bc7ada07abbee3e347fa2fb6` | no |
| `bench-shd002` | `Build/qa-011/D3/20261116T032055Z/logs/bench-shd002.log` | 3545472 | `a9393c36d10e39ad91862221631c60334fc1fb905d92cfca00215ec0244da7b9` | no |
| `bench-shd002` | `Build/qa-011/D3/20261116T032055Z/xcresult/bench-shd002.xcresult` | 282812 | `31013f7041af87599e4cdc89caccf2786c05ffe6454b41122c3d5f3664221b35` | no |
