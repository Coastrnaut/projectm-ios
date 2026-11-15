# QA-011 device run D2 20261115T192442Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1a9a1724869813ac82890fa16b434b93ac6ff54b` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T19:24:42Z, finished 2026-11-15T19:27:57Z
- Summary: pass 2, not-run 1
- Record SHA-256: `6c6ed88882f0afdad7b9eb225bad7232718a0b37ad1cb4bb7762e2f66761c6db`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `xctest-materials` | pass | 63.7 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped |
| `xctest-angle-layer` | not-run | 0.0 | part of CMP-001-T20 | ANGLERenderingTests/ProjectMLayerTests, ANGLERenderingTests/ClientBufferSpikeTests: no app-hosted device bundle (DeviceTests.yml) |
| `bench-shd002` | pass | 129.0 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D2/20261115T192442Z/xcresult/bench-shd002.xcresult / SHD002_BENCH device Apple M5 GPU: 12-node graph median 2.227999999831809 ms, ma |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `xctest-materials` | `Build/qa-011/D2/20261115T192442Z/logs/xctest-materials.log` | 3184908 | `303728c11a42ba5da9187a363027bdc3029517822ea962a4864709c45c7dedec` | no |
| `xctest-materials` | `Build/qa-011/D2/20261115T192442Z/xcresult/xctest-materials.xcresult` | 385369 | `4eb03b0e1265492cb4e6242c13c0961453555ef4b2f9b410e1a23befb3175acf` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T192442Z/logs/bench-shd002.log` | 3330592 | `959b4b5a5eb297bfa08225b3216f71b5e0f9186fbd2bf175256534b181f4fca5` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T192442Z/xcresult/bench-shd002.xcresult` | 260132 | `e2e635d0635ea0fb69390cac0c39c919c12d6097cc25451c8624d684af01d27b` | no |
