# QA-011 device run D1 20261115T204015Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1d055b69e4fc4bc76f47bc3a581861a61e5c36dd`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T20:40:15Z, finished 2026-11-15T20:55:43Z
- Summary: pass 14, fail 1
- Record SHA-256: `6fc9acfa54888d36bf093f8e2b7b2ab4e2fe145eb9439e12266a9710a53cd959`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 81.9 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T204140Z.json |
| `launches-sc015` | pass | 81.8 | QA-010-T12 | 11 launches recorded |
| `warmstart-perf009` | pass | 142.1 | PERF-009-T16 | cold 10 launches, library ready 245.3 ms; warm 11, 172.6 ms |
| `autorun-sc009` | pass | 76.5 | AUD-014-T32 | report automation-sc009-2026-11-15T204644Z.json |
| `autorun-perf012` | pass | 88.4 | part of QA-010-T12 | report performance-perf012-2026-11-15T204813Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall fail |
| `xctest-goldens` | pass | 88.2 | QA-003-T17 | 134 tests, 0 failures, 3 skipped; QA-006 qa006-scene-soak [iOS, deviceAllocatedSize]: pass; cycles measured 10; slope 0 B/cycle (limit 65536); high-water 7880704 (warm-up 7880704, bound 9977856) / QA-006 qa006-scene-soak cycle 0: high-water 7782400, end 7766016, pool live 786432, misses 8, footprint |
| `xctest-soak-600` | pass | 101.9 | QA-006-T13 | 1 tests, 0 failures, 0 skipped; QA-006 qa006-scene-soak-600s [iOS, deviceAllocatedSize]: pass; cycles measured 190; slope 0 B/cycle (limit 65536); high-water 2375680 (warm-up 2375680, bound 44 / QA-006 qa006-scene-soak-600s cycle 0: high-water 2277376, end 2260992, pool live 786432, misses 8, footpr |
| `xctest-angle-layer` | pass | 10.6 | part of CMP-001-T20 | 7 tests, 0 failures, 0 skipped |
| `bench-shd002` | pass | 133.7 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T204015Z/xcresult/bench-shd002.xcresult / SHD002_BENCH device Apple A16 GPU: 12-node graph median 9.475375001784414 ms, m |
| `bench-cmp008` | pass | 16.1 | CMP-008-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T204015Z/xcresult/bench-cmp008.xcresult / CMP-008 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-008 |
| `bench-cmp009` | pass | 12.8 | CMP-009-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T204015Z/xcresult/bench-cmp009.xcresult / CMP-009 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-009 |
| `bench-cmp010` | pass | 12.6 | CMP-010-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T204015Z/xcresult/bench-cmp010.xcresult / CMP-010 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-010 |
| `bench-expression` | pass | 10.0 | SHD-010-T13 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T204015Z/xcresult/bench-expression.xcresult / SHD-010 bench add: 16 formulas, cost 2032/frame, 3302 ns/frame, 1.62 ns/uni |
| `xctest-offline-export` | pass | 51.9 | REC-013-T14 | 4 tests, 0 failures, 0 skipped |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/automation-perf001-2026-11-15T204140Z.json` | 3148 | `06f35dc15ae98555e1d3e3ccdd37d3b96c6d112ff1b9006a83fb3b2e761ad73d` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/sc015.json` | 219 | `e7498fa1a5a176034caa5c803309426217c0e5fdfa1c84a659dbe84a7632b286` | yes |
| `warmstart-perf009` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/perf009.json` | 3449 | `9e9d62a5a78c69a42c87f6071d220eb7b893cfb60e61b4f531c4b3f48aaee53b` | yes |
| `warmstart-perf009` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/perf009-summary.json` | 342 | `3f38bdf378a96bd928a1fa57908ea3263940b168c31db72bfd1905bfdf89422a` | yes |
| `autorun-sc009` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/automation-sc009-2026-11-15T204644Z.json` | 2434 | `6f618581c15951e0e5195073fcae3de7827acefe44abe6cd0f4e054b5633a19d` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/performance-perf012-2026-11-15T204813Z.json` | 2488 | `a706b4d77bd763b574a053ea5ccdaf5bf2043bf2eb42d5ed7cdfce38775e3eb1` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/performance-verdict.json` | 1758 | `9054ddf44ca35e622153cb94fb53ab0b7e6fb05f3b9d868abfcd5088a546a5c9` | yes |
| `xctest-goldens` | `Build/qa-011/D1/20261115T204015Z/logs/xctest-goldens.log` | 3433206 | `634904df8bc345d06da008348c3b805b69c67f4f4f8e63460f6dc2b3d8285c53` | no |
| `xctest-goldens` | `Build/qa-011/D1/20261115T204015Z/xcresult/xctest-goldens.xcresult` | 548587 | `785203bcb5f80097dbb78ac7b5daf6186622a9064b97d4a881a5c7245d6c56ca` | no |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/xctest-goldens-1763B80D-B6B6-457F-8FCF-618A62535D0A.json` | 5516 | `12e4fae7785cc26a3d66b971d4c46019515a20528a6d5675a90442e0973c4449` | yes |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/xctest-goldens-33D6F644-3BAD-432A-8CEA-3232D8FA189B.json` | 24614 | `6914082ca53a050a6fbbb94bfd4ecc26bbe7a4a3db9a05d92b935e357e6a351f` | yes |
| `xctest-goldens` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/xctest-goldens-EFCC3E8F-58D9-4FFA-837B-0E21578E234D.json` | 6408 | `becfdc02000c61323547cc81905bb8b17bb339b007dff996dbc365a9523461ed` | yes |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T204015Z/logs/xctest-soak-600.log` | 350013 | `b0f15d146b5609949ee7f70d997feef1806381f82476b0b5f0293d9a1fec9b57` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T204015Z/xcresult/xctest-soak-600.xcresult` | 61771 | `c45dde5a57e04d4922b4d3e07c4fada4988d0d7c5f43a12af30a93cf9e34ef61` | no |
| `xctest-soak-600` | `docs/test-reports/qa-011/runs/D1/20261115T204015Z/artifacts/xctest-soak-600-28B849ED-4EF9-438A-8FB7-3BB1BF0C5BF0.json` | 235219 | `d1e7b9de3fcb8ca47e5a6eeee1fdc2840d450e9edf2982ba70c666fda4f74758` | yes |
| `xctest-angle-layer` | `Build/qa-011/D1/20261115T204015Z/logs/xctest-angle-layer.log` | 160865 | `61dd8947bd851f84b189792621a50336029571caae48f9abfa71bcc4a69091dd` | no |
| `xctest-angle-layer` | `Build/qa-011/D1/20261115T204015Z/xcresult/xctest-angle-layer.xcresult` | 45583 | `2a92e2743e5516e291adab7a3235f85ff2ab2cb6a13fa9489e4c4b9d0dc5f2c7` | no |
| `bench-shd002` | `Build/qa-011/D1/20261115T204015Z/logs/bench-shd002.log` | 3545915 | `a8ae1a95c96844ba3a628c56e344d462fb1a7fe5a44490714c5a26652fa7037b` | no |
| `bench-shd002` | `Build/qa-011/D1/20261115T204015Z/xcresult/bench-shd002.xcresult` | 281462 | `260cc497ae3bd183d93dcc39439a30216eef7132d83942e61c00d57fbf325fbd` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261115T204015Z/logs/bench-cmp008.log` | 325793 | `576a87e1bc31b4e1085600a750d6f7ee703155e9f9e2a17b1ffe086031d416ee` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261115T204015Z/xcresult/bench-cmp008.xcresult` | 50179 | `ccda6218f393487eba8d4677f45b44fcc07ab5140d1c99e725df99e54daa3660` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261115T204015Z/logs/bench-cmp009.log` | 165802 | `2fd9d0fa141317821e2691bd543dc7f6d3dde3180f0a5f25879f3549d6ebe22a` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261115T204015Z/xcresult/bench-cmp009.xcresult` | 39449 | `34ce85d42a77370be96be3573bea69e47bfc3c32a2d06247b04724022dd80fe7` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261115T204015Z/logs/bench-cmp010.log` | 164094 | `a8cef0681a771881834f769cfb69313372920272177a2df5149da9688c1359c5` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261115T204015Z/xcresult/bench-cmp010.xcresult` | 39067 | `0872a6c37409e43bbe16c4ed2bff596b2682625aa31bc42dee1400da8c6d4ecf` | no |
| `bench-expression` | `Build/qa-011/D1/20261115T204015Z/logs/bench-expression.log` | 160530 | `d0ae958cc84249f18efe99d586c8bbc4addecf5dc3b1663d95446faccfd61b63` | no |
| `bench-expression` | `Build/qa-011/D1/20261115T204015Z/xcresult/bench-expression.xcresult` | 39029 | `4814a59f6069611b59c3c9620616e1ce1885acb31d418a8e74626d8a7d8addcb` | no |
| `xctest-offline-export` | `Build/qa-011/D1/20261115T204015Z/logs/xctest-offline-export.log` | 2857993 | `4274ca5c28fda25c96078e8188e177307041f5b78e00f71c0c37de83a4f4f90f` | no |
| `xctest-offline-export` | `Build/qa-011/D1/20261115T204015Z/xcresult/xctest-offline-export.xcresult` | 371300 | `303f2006fb2a2d71d20b01d69afccc0b187fbcc8b7afbc89722bb15c1f0b4391` | no |
