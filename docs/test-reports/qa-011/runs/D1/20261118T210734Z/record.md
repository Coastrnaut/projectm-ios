# QA-011 device run D1 20261118T210734Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `d91ab2a71db70a9da93730108d4a17be31950a1a` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T21:07:34Z, finished 2026-11-18T21:10:59Z
- Summary: pass 1
- Record SHA-256: `3799a8c8eafe03e917f5571421baad7b20652a8307fdbcc4fa1398716bdb5010`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-rec003-encoder` | pass | 203.8 | part of REC-003-T23 | 2 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261118T210734Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-rec003-encoder` | `Build/qa-011/D1/20261118T210734Z/logs/bench-rec003-encoder.log` | 3667207 | `60499e14a80f82c5630550f791de21ce3ac230ccc440669d1b7ce037fabc57b4` | no |
| `bench-rec003-encoder` | `Build/qa-011/D1/20261118T210734Z/xcresult/bench-rec003-encoder.xcresult` | 290151 | `2fb579c52664e96783273fdebec8ccd26fa4b97fe48d44a1915ac65ef321844c` | no |
