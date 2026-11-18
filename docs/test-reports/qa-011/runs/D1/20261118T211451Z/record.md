# QA-011 device run D1 20261118T211451Z

- Target: device iPhone77 `iPhone15,4`, OS 27.0.1 (24A446), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `d91ab2a71db70a9da93730108d4a17be31950a1a` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T21:14:51Z, finished 2026-11-18T21:18:34Z
- Summary: pass 1
- Record SHA-256: `37a19119feb72d72b1c3d18af3eef34ea1e15f957e2502c90f081e7bd933f779`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-rec003-encoder` | pass | 222.6 | part of REC-003-T23 | 3 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D1/20261118T211451Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-rec003-encoder` | `Build/qa-011/D1/20261118T211451Z/logs/bench-rec003-encoder.log` | 3667619 | `d288a0a275f7a555117ef8bac8ab4fad91eebd9059aa3fda1c82b1a2e6ee617a` | no |
| `bench-rec003-encoder` | `Build/qa-011/D1/20261118T211451Z/xcresult/bench-rec003-encoder.xcresult` | 291325 | `b3be015fcbbd0c9e523d8d99931fc0bbb515fb8fa20c3b27dd20bf164df5859a` | no |
