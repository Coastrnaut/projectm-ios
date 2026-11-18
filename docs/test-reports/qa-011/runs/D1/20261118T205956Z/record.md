# QA-011 device run D1 20261118T205956Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `d91ab2a71db70a9da93730108d4a17be31950a1a` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T20:59:56Z, finished 2026-11-18T21:02:49Z
- Summary: pass 1
- Record SHA-256: `9b83ac7366ac05ad14962e82cf02c984d17e9b19b33755934e79e11992d261ed`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-rec003-encoder` | pass | 172.7 | part of REC-003-T23 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261118T205956Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-rec003-encoder` | `Build/qa-011/D1/20261118T205956Z/logs/bench-rec003-encoder.log` | 3666499 | `e1cb475aededf91940e023e11dcedd73a2f7e24b41f0969099ac1c1c8d2f8e17` | no |
| `bench-rec003-encoder` | `Build/qa-011/D1/20261118T205956Z/xcresult/bench-rec003-encoder.xcresult` | 291550 | `fd1d2d48b83b34fe790ff83c0b6400a275f3cfb7d80ce6259bceda7ec2269a1e` | no |
