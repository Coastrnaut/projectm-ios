# QA-011 device run D2 20261115T205605Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1d055b69e4fc4bc76f47bc3a581861a61e5c36dd` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T20:56:05Z, finished 2026-11-15T20:58:17Z
- Summary: pass 1
- Record SHA-256: `b667a11daf18473aec327d11c5f03a5a38adb08d21b6184c4d040078c67e42dc`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-shd002` | pass | 130.8 | SHD-002-T24 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D2/20261115T205605Z/xcresult/bench-shd002.xcresult / SHD002_BENCH device Apple M5 GPU: 12-node graph median 2.2277916668826947 ms, m |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-shd002` | `Build/qa-011/D2/20261115T205605Z/logs/bench-shd002.log` | 3549509 | `35a2860eeb19c35c0695b7afb3a3f8bba96c9e984f2f93f2c9ae0a7f05ce6717` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T205605Z/xcresult/bench-shd002.xcresult` | 278192 | `f61c802b6f188487fe218f6ceb4ae8a279036113cc00bb2c4f2e75659ced8e1d` | no |
