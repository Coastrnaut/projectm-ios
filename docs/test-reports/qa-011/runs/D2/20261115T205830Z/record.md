# QA-011 device run D2 20261115T205830Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1d055b69e4fc4bc76f47bc3a581861a61e5c36dd` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T20:58:30Z, finished 2026-11-15T21:06:04Z
- Summary: pass 7
- Record SHA-256: `e1ce237a405d0faf580f378229f168fb1f0c0ab6a1da3a8b4cc273e04b633a66`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 76.2 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T205949Z.json |
| `launches-sc015` | pass | 74.8 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 85.7 | part of QA-010-T12 | report performance-perf012-2026-11-15T210231Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-materials` | pass | 49.0 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped |
| `xctest-angle-layer` | pass | 10.9 | part of CMP-001-T20 | 7 tests, 0 failures, 0 skipped |
| `bench-shd002` | pass | 148.6 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D2/20261115T205830Z/xcresult/bench-shd002.xcresult / SHD002_BENCH device Apple M5 GPU: 12-node graph median 2.2278750002442393 ms, m |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261115T205830Z/artifacts/automation-perf001-2026-11-15T205949Z.json` | 3182 | `b2941f0761efe1251b80d947250cc4d03b915c698f109c7e9518cab115e0385d` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261115T205830Z/artifacts/sc015.json` | 220 | `fc9a3186d145f0e7029f19c71b3d37c6815f994085b5534e6cd295f995dd718b` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261115T205830Z/artifacts/performance-perf012-2026-11-15T210231Z.json` | 2520 | `ffa422ad9e90e2fc59c645ae4a4e9e8d4ccc6dc14ee533de66ad44b749bbcf2f` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261115T205830Z/artifacts/performance-verdict.json` | 1756 | `31f84419485a972650ef53bc52f6ea5c99735b6064a08bcf5c11eb3283e928c5` | yes |
| `xctest-materials` | `Build/qa-011/D2/20261115T205830Z/logs/xctest-materials.log` | 3373238 | `ed199da7622e934d936bd30b3eb153c6d2cd593ca5ce04944522c1724d217bca` | no |
| `xctest-materials` | `Build/qa-011/D2/20261115T205830Z/xcresult/xctest-materials.xcresult` | 401930 | `774b7f08c65b4afeb7b0116177fba678c18cfb278ae233d13a02fe66df89f09e` | no |
| `xctest-angle-layer` | `Build/qa-011/D2/20261115T205830Z/logs/xctest-angle-layer.log` | 294907 | `be96410280fcad944770ac7b743f228f9deaf07b0358c972a4452ba7733c7fea` | no |
| `xctest-angle-layer` | `Build/qa-011/D2/20261115T205830Z/xcresult/xctest-angle-layer.xcresult` | 53299 | `bbc0684394b5f3453da395af2574a346fe9a144f8725f473778f688d25b97e40` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T205830Z/logs/bench-shd002.log` | 3546266 | `a8bf1a53f6c5a01c5345359ff24c97e1db76940fed4a8c55302437b86efa62d9` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T205830Z/xcresult/bench-shd002.xcresult` | 279692 | `59756438484783a26bca0c7fc669ed1e92225ca7ff129f8af73fc7e48432f7ce` | no |
