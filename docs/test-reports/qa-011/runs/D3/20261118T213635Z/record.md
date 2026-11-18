# QA-011 device run D3 20261118T213635Z

- Target: device iPadC `iPad15,7`, OS 26.5 (23F77), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `d91ab2a71db70a9da93730108d4a17be31950a1a` (dirty tree)
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-18T21:36:35Z, finished 2026-11-18T21:39:31Z
- Summary: pass 1
- Record SHA-256: `f5b54bda1b73612395ba4eccebb60ae415af7f38ad6b128290994ea7181e7f97`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `bench-rec003-encoder` | pass | 174.7 | part of REC-003-T23 | 1 tests, 0 failures, 0 skipped; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D3/20261118T213635Z/xcresult/bench-rec003-encoder.xcresult / 41 /             throw XCTSkip("on-demand bench: set SHD002_BENCH=1") / |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `bench-rec003-encoder` | `Build/qa-011/D3/20261118T213635Z/logs/bench-rec003-encoder.log` | 3666851 | `62b7dc224178be8e5d2ed780e86f407f7e36e619adb313de67d179012658cd5f` | no |
| `bench-rec003-encoder` | `Build/qa-011/D3/20261118T213635Z/xcresult/bench-rec003-encoder.xcresult` | 290229 | `1b3c48429b468ec4695bc134449f8852f04b1617fb11a4006fda0322611fc79d` | no |
