# QA-011 device run D3 20261118T211431Z

- Target: device iPadC `iPad15,7`, OS 26.5 (23F77), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `d91ab2a71db70a9da93730108d4a17be31950a1a` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T21:14:31Z, finished 2026-11-18T21:18:17Z
- Summary: pass 1
- Record SHA-256: `21fa8d210443eb72f065fb22f8f848462ff064ebddb8047078bc7c8adde05372`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-rec003-encoder` | pass | 226.1 | part of REC-003-T23 | 3 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D3/20261118T211431Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-rec003-encoder` | `Build/qa-011/D3/20261118T211431Z/logs/bench-rec003-encoder.log` | 3667654 | `3b9875a76b71240ec2c254a8948dfa778f5f5f45a76c55a5ab003878964a6a60` | no |
| `bench-rec003-encoder` | `Build/qa-011/D3/20261118T211431Z/xcresult/bench-rec003-encoder.xcresult` | 291672 | `c177c3c6c8b18ae0de48d04a675bbdd054c4d901a5c23ae7a802d054ec16606e` | no |
