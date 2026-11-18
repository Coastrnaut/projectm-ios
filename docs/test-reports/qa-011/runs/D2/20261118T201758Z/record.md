# QA-011 device run D2 20261118T201758Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6ee08e69f7c499ee0fa08cef1fbf8dfc77f1ed4d`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T20:17:58Z, finished 2026-11-18T20:21:41Z
- Summary: pass 2
- Record SHA-256: `001307f83123c9ed0c49760155298df8c409281f01cd9dd0968c89e046503ab4`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `xctest-materials` | pass | 55.2 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped; 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set |
| `bench-shd002` | pass | 166.6 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D2/20261118T201758Z/xcresult/bench-shd002.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /    |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `xctest-materials` | `Build/qa-011/D2/20261118T201758Z/logs/xctest-materials.log` | 3386451 | `0d74bbf99055da23a8e0f60a474dac0ec128d9b0106a6727da6bcf43ffdd21b8` | no |
| `xctest-materials` | `Build/qa-011/D2/20261118T201758Z/xcresult/xctest-materials.xcresult` | 406702 | `9e08abae88049d2dc8ed907f9ccf165575bf4aca3e4e04d3a43972752a9c5fc5` | no |
| `bench-shd002` | `Build/qa-011/D2/20261118T201758Z/logs/bench-shd002.log` | 3560551 | `25a5f49e08512330831500cd67183f3a4f560a0d282dc2ae674b75a98ddd6287` | no |
| `bench-shd002` | `Build/qa-011/D2/20261118T201758Z/xcresult/bench-shd002.xcresult` | 278912 | `3a5354df426b82c5d4d42b28a477518c230b7726cedbe94554dd5ac37c53fcff` | no |
