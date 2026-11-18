# QA-011 device run D3 20261118T201849Z

- Target: device iPadC `iPad15,7`, OS 26.5 (23F77), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `6ee08e69f7c499ee0fa08cef1fbf8dfc77f1ed4d`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T20:18:49Z, finished 2026-11-18T20:22:32Z
- Summary: pass 2
- Record SHA-256: `e386a892c79899f61512eb9dcda6d69a72325ae89ebad39d5a97ba572a792401`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `xctest-materials` | pass | 62.6 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped; 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /             throw XCTSkip("on-demand bench: set |
| `bench-shd002` | pass | 158.7 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D3/20261118T201849Z/xcresult/bench-shd002.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / 41 /    |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `xctest-materials` | `Build/qa-011/D3/20261118T201849Z/logs/xctest-materials.log` | 3385966 | `af5bbbd3e7a9011f7a5ba308142b6a5d7e7f35f632b8352b4028bbc4fbc04c32` | no |
| `xctest-materials` | `Build/qa-011/D3/20261118T201849Z/xcresult/xctest-materials.xcresult` | 403990 | `2e0f4e941307c28e2acd47a354d60b93e5762eb87bfc225774a76b07715e34ed` | no |
| `bench-shd002` | `Build/qa-011/D3/20261118T201849Z/logs/bench-shd002.log` | 3560347 | `68dd9808dc5bc4b6dbb54061ed6be1619603e9df1da16bad3305bef365b76991` | no |
| `bench-shd002` | `Build/qa-011/D3/20261118T201849Z/xcresult/bench-shd002.xcresult` | 282019 | `7da8ac98fad075880f9666669c4cdba63e32bf6a1d15d8b5911583e5e9f86e9e` | no |
