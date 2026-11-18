# QA-011 device run D3 20261118T210755Z

- Target: device iPadC `iPad15,7`, OS 26.5 (23F77), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `d91ab2a71db70a9da93730108d4a17be31950a1a` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T21:07:55Z, finished 2026-11-18T21:11:13Z
- Summary: pass 1
- Record SHA-256: `24cf4c62761fdec2ab1673d5d4e1a9d87ee395bd86cf7e303afa6fd6ae6cd191`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-rec003-encoder` | pass | 197.5 | part of REC-003-T23 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D3/20261118T210755Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-rec003-encoder` | `Build/qa-011/D3/20261118T210755Z/logs/bench-rec003-encoder.log` | 3667299 | `d2b59da238c72de812f783741ecf4469b1a6586a710bb409b824f7129fe397bf` | no |
| `bench-rec003-encoder` | `Build/qa-011/D3/20261118T210755Z/xcresult/bench-rec003-encoder.xcresult` | 288512 | `455abcdfd83483d3163289ef4aaaea4c04a605335c4e0f124b5ce93c218c20bf` | no |
