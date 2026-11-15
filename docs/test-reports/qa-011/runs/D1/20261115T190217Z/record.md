# QA-011 device run D1 20261115T190217Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1a9a1724869813ac82890fa16b434b93ac6ff54b`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:02:17Z, finished 2026-11-15T19:10:12Z
- Summary: pass 5, fail 9
- Record SHA-256: `4729e63831c243c10bb3bbca7660544640bb060f650c5361d39626d9eb12aa1a`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 90.7 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T190349Z.json |
| `launches-sc015` | pass | 75.0 | QA-010-T12 | 11 launches recorded |
| `warmstart-perf009` | pass | 140.8 | PERF-009-T16 | cold 10 launches, library ready 240.2 ms; warm 11, 172.5 ms |
| `autorun-sc009` | pass | 76.0 | AUD-014-T32 | report automation-sc009-2026-11-15T190843Z.json |
| `thresholds` | fail | 0.0 | QA-010-T12 | QA-010 overall incomplete |
| `xctest-goldens` | fail | 2.8 | QA-003-T17 | no test summary in the log; exit 70 |
| `xctest-soak-600` | fail | 3.3 | QA-006-T13 | no test summary in the log; exit 70 |
| `xctest-angle-layer` | fail | 1.3 | part of CMP-001-T20 | no test summary in the log; exit 70 |
| `bench-shd002` | fail | 4.1 | SHD-002-T24 | no test summary in the log; exit 70; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme Compositor -destination platform=iOS,id=00008120-001E4C5C3A42201E -derivedDataPath /U / Build/qa-011/D1/20261115T190217Z/xcresult/bench-shd002.xcresult |
| `bench-cmp008` | fail | 2.8 | CMP-008-T19 | no test summary in the log; exit 70; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme Compositor -destination platform=iOS,id=00008120-001E4C5C3A42201E -derivedDataPath /U / Build/qa-011/D1/20261115T190217Z/xcresult/bench-cmp008.xcresult |
| `bench-cmp009` | fail | 2.8 | CMP-009-T19 | no test summary in the log; exit 70; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme Compositor -destination platform=iOS,id=00008120-001E4C5C3A42201E -derivedDataPath /U / Build/qa-011/D1/20261115T190217Z/xcresult/bench-cmp009.xcresult |
| `bench-cmp010` | fail | 2.7 | CMP-010-T19 | no test summary in the log; exit 70; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme Compositor -destination platform=iOS,id=00008120-001E4C5C3A42201E -derivedDataPath /U / Build/qa-011/D1/20261115T190217Z/xcresult/bench-cmp010.xcresult |
| `bench-expression` | fail | 1.6 | SHD-010-T13 | no test summary in the log; exit 70; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme ParameterGraph -destination platform=iOS,id=00008120-001E4C5C3A42201E -derivedDataPat / Build/qa-011/D1/20261115T190217Z/xcresult/bench-expression.xcresult |
| `xctest-offline-export` | pass | 56.2 | REC-013-T14 | 4 tests, 0 failures, 0 skipped |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D1/20261115T190217Z/artifacts/automation-perf001-2026-11-15T190349Z.json` | 1873 | `59b9027f5db6a255a1c30036353686af681cfb9bd16a6af1fc8d32a795c15cec` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D1/20261115T190217Z/artifacts/sc015.json` | 221 | `13a25646160d62bbec6d59bf509fc4755d753e95fcc92b7e238ecf1969bb46d8` | yes |
| `warmstart-perf009` | `docs/test-reports/qa-011/runs/D1/20261115T190217Z/artifacts/perf009.json` | 3454 | `d98d54f05765b8b8558980c80f04a86eec62a78958c41a89a13568ddc88fbc52` | yes |
| `warmstart-perf009` | `docs/test-reports/qa-011/runs/D1/20261115T190217Z/artifacts/perf009-summary.json` | 342 | `eb726b0c0576b687464ccdf04011735f1a54300792b6d3d9fea1a302fa6cc718` | yes |
| `autorun-sc009` | `docs/test-reports/qa-011/runs/D1/20261115T190217Z/artifacts/automation-sc009-2026-11-15T190843Z.json` | 2434 | `3ec76f24765155d3b39af7d8ad72c50dc31a8942252595ca92956f53c74c1ac3` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D1/20261115T190217Z/artifacts/performance-verdict.json` | 1567 | `98e8a772926b9c7a023261b0089166044d79e39464ea9b218ebcda73fe0fac12` | yes |
| `xctest-goldens` | `Build/qa-011/D1/20261115T190217Z/logs/xctest-goldens.log` | 2142 | `2cdb9163326f0a66c44cb2fdd2029fff6d29bd1fc4a2d7f8f46fb3626599077e` | no |
| `xctest-goldens` | `Build/qa-011/D1/20261115T190217Z/xcresult/xctest-goldens.xcresult` | 3004 | `0d0b7b786fb2660d11a586e0038a72bc67eed3e57df3a7a6755fc44f96b9af3b` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T190217Z/logs/xctest-soak-600.log` | 2217 | `17c0b3237fcc3fbd458412e4aeeeba19e77a2d7c09f0d8d61289f0f125f777ff` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T190217Z/xcresult/xctest-soak-600.xcresult` | 2994 | `76fd06fcc674e06c22f452e053fad8593f4fd37354432c9291736b79afc5dfae` | no |
| `xctest-angle-layer` | `Build/qa-011/D1/20261115T190217Z/logs/xctest-angle-layer.log` | 2461 | `3309a13b6cc6c714feb5232e42b3392663b95e9bdcafa5090548ec610645e05d` | no |
| `xctest-angle-layer` | `Build/qa-011/D1/20261115T190217Z/xcresult/xctest-angle-layer.xcresult` | 3000 | `2203b5c90cac3b42c0519871fd5e6df6d66dbba35f7a039ffe5b1bce99d8030d` | no |
| `bench-shd002` | `Build/qa-011/D1/20261115T190217Z/logs/bench-shd002.log` | 2116 | `bb66b0818b5255b06668468af222fe7b4a250cafeda4655fcfda22f3bbc8d583` | no |
| `bench-shd002` | `Build/qa-011/D1/20261115T190217Z/xcresult/bench-shd002.xcresult` | 3003 | `86e3df5b16793bcaecb087164245f925e936412eecc73b97a714c9a4c6c6a6b9` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261115T190217Z/logs/bench-cmp008.log` | 2146 | `e1cccaa52424f059cabb53f3f470e1daaffc1627ed365d3b3bbe72eb0c4b22de` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261115T190217Z/xcresult/bench-cmp008.xcresult` | 2996 | `82f9971206b6520faa6f163a79a938c2308bf0dc3c13ccf2bccdf81eadce7782` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261115T190217Z/logs/bench-cmp009.log` | 2144 | `342a9add97ea57d1b4f74ec08471dd5cb0c46027bab4bdd21e8c0f14075356a2` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261115T190217Z/xcresult/bench-cmp009.xcresult` | 2993 | `ead73092e8d01016938d65d4ff2bc596a0bc4e5d4a28556b0018476b335b7718` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261115T190217Z/logs/bench-cmp010.log` | 2146 | `41e77c669da535bee2c0157ce1926310806811d42a2796fd00546533a2ca1e3f` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261115T190217Z/xcresult/bench-cmp010.xcresult` | 2993 | `ce03cc44a52bdd97d043e6a3a650899b0a61f64e38e77ecf138c73af0e7a5dd4` | no |
| `bench-expression` | `Build/qa-011/D1/20261115T190217Z/logs/bench-expression.log` | 1660 | `9acda62d398729230948196c02a3d3476b8f619d0807aa2539cbde8e3063a353` | no |
| `bench-expression` | `Build/qa-011/D1/20261115T190217Z/xcresult/bench-expression.xcresult` | 3019 | `557d0eb6bf9fdf50c525b4a60d78e4739ad8c2574a6cfa087bf94068be1ea352` | no |
| `xctest-offline-export` | `Build/qa-011/D1/20261115T190217Z/logs/xctest-offline-export.log` | 2857358 | `e91fd2ef6f4882657937a32e24a60888af00d6b7f6669145374df5aa199f4b78` | no |
| `xctest-offline-export` | `Build/qa-011/D1/20261115T190217Z/xcresult/xctest-offline-export.xcresult` | 370597 | `7c5fd61e5db7e56f2370686f84226e5b246906293496bd2a9c0b3d4f4bcdb4b7` | no |
