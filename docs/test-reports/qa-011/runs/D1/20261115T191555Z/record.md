# QA-011 device run D1 20261115T191555Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1a9a1724869813ac82890fa16b434b93ac6ff54b` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:15:55Z, finished 2026-11-15T19:22:06Z
- Summary: pass 5, fail 2, not-run 1
- Record SHA-256: `adcf5cfa04ace78e1f343604a16978558b3f96d9c235a0b8d5d2eb911fdc7768`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `xctest-goldens` | fail | 122.9 | QA-003-T17 | 1 tests, 0 failures, 16 skipped; exit 65; Packages/Compositor/Tests/CompositorTests/LayerBlendCompositeTests.swift:394: -[CompositorDeviceTests.LayerBlendComposit / Packages/Compositor/Tests/CompositorTests/LayerColorKeyCompositeTests.swift:292: -[CompositorDeviceTests.LayerColorKeyCo / Packages/Com |
| `xctest-soak-600` | fail | 17.7 | QA-006-T13 | 1 tests, 1 failures, 0 skipped; exit 65 |
| `xctest-angle-layer` | not-run | 0.0 | part of CMP-001-T20 | ANGLERenderingTests/ProjectMLayerTests, ANGLERenderingTests/ClientBufferSpikeTests: no app-hosted device bundle (DeviceTests.yml) |
| `bench-shd002` | pass | 155.9 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T191555Z/xcresult/bench-shd002.xcresult / SHD002_BENCH device Apple A16 GPU: 12-node graph median 9.436291642487049 ms, m |
| `bench-cmp008` | pass | 23.8 | CMP-008-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T191555Z/xcresult/bench-cmp008.xcresult / CMP-008 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-008 |
| `bench-cmp009` | pass | 16.8 | CMP-009-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T191555Z/xcresult/bench-cmp009.xcresult / CMP-009 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-009 |
| `bench-cmp010` | pass | 16.4 | CMP-010-T19 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T191555Z/xcresult/bench-cmp010.xcresult / CMP-010 GPU time per frame, 1920 × 1080 (ms): / case / median / p95 / / CMP-010 |
| `bench-expression` | pass | 10.2 | SHD-010-T13 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261115T191555Z/xcresult/bench-expression.xcresult / SHD-010 bench add: 16 formulas, cost 2032/frame, 3309 ns/frame, 1.63 ns/uni |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `xctest-goldens` | `Build/qa-011/D1/20261115T191555Z/logs/xctest-goldens.log` | 3647554 | `109b8ec932d3253a2318a0338e73afd0a6366b2da802687c18660951db0d9380` | no |
| `xctest-goldens` | `Build/qa-011/D1/20261115T191555Z/xcresult/xctest-goldens.xcresult` | 1758539 | `9ae2241e6290973533c9e592f48f5c898e8284899451a96fbeb5e75eb17f9494` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T191555Z/logs/xctest-soak-600.log` | 272652 | `851a100e378e73d9ff0050be2aab83543ca697bef30017cc26ee833ce0355671` | no |
| `xctest-soak-600` | `Build/qa-011/D1/20261115T191555Z/xcresult/xctest-soak-600.xcresult` | 49098 | `ae13049780a29baf26cf3e12cb9161431acefa1162839359c1f096aef423f3d1` | no |
| `bench-shd002` | `Build/qa-011/D1/20261115T191555Z/logs/bench-shd002.log` | 3327844 | `ef5862643533afaa0a209340fac8831c155ad6f0298e567f056a7e23f121a970` | no |
| `bench-shd002` | `Build/qa-011/D1/20261115T191555Z/xcresult/bench-shd002.xcresult` | 263096 | `754776e53f202a90cebf9244f94b1e2df375323a9178e48342443d08ed242eaf` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261115T191555Z/logs/bench-cmp008.log` | 264509 | `94be4b1db0604a1b05e96c7915269b6ecbeb569546ca402e5ef75b123a4002a8` | no |
| `bench-cmp008` | `Build/qa-011/D1/20261115T191555Z/xcresult/bench-cmp008.xcresult` | 45891 | `1dbec0d158b8f1efc07a5742294556b10ba4e4e63d568603b36d4ea222513df5` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261115T191555Z/logs/bench-cmp009.log` | 148814 | `4e93ea139ade2c027278aa7be8e23cdad5742638d497874b4175c180f622eabf` | no |
| `bench-cmp009` | `Build/qa-011/D1/20261115T191555Z/xcresult/bench-cmp009.xcresult` | 38189 | `317f0ab1fa44edead4e86fa61266232a05bb0dcb8c2e9e89480392a2ba2fea62` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261115T191555Z/logs/bench-cmp010.log` | 146347 | `b89c8c3183e4be592cbddb7810dba6cd43cc21ddc4a0a095f07e448c7df12320` | no |
| `bench-cmp010` | `Build/qa-011/D1/20261115T191555Z/xcresult/bench-cmp010.xcresult` | 37958 | `a5d5aff53b36c1b31edbb5c609838c715d406f34437363f074692e2d4961d62d` | no |
| `bench-expression` | `Build/qa-011/D1/20261115T191555Z/logs/bench-expression.log` | 146477 | `fcc73935021140cccdc234b5d2684d63f98dd32287c4ebc9174222b88611782c` | no |
| `bench-expression` | `Build/qa-011/D1/20261115T191555Z/xcresult/bench-expression.xcresult` | 37861 | `33445b2b5e8d53e67712aa03f46998a0d15d2ac24508deee2bbdc272409d549f` | no |
