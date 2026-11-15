# QA-011 device run D2 20261115T204015Z

- Target: device iPad77 `iPad17,3`, OS 27.2 (24B119), state connected
- App: `org.projectmios.ProjectMiOS` 1.1 (2), Release+PROJECTM_AUTOMATION, commit `1d055b69e4fc4bc76f47bc3a581861a61e5c36dd`
- Signing: Apple Development; team WX58SV9Y9J
- Host: Xcode 27.2 Build version 27B52, macOS 27.2.1
- Started 2026-11-15T20:40:15Z, finished 2026-11-15T20:47:19Z
- Summary: pass 6, fail 1
- Record SHA-256: `1ea116398b31408addebc3f29d0f285a39d669359830f6f1030bc7ddd1110256`

| Case | Status | Seconds | Closes | Detail |
|---|---|---|---|---|
| `autorun-perf001` | pass | 79.5 | PERF-001-T16, PERF-002-T13, QA-010-T12 | report automation-perf001-2026-11-15T204134Z.json |
| `launches-sc015` | pass | 76.7 | QA-010-T12 | 11 launches recorded |
| `autorun-perf012` | pass | 89.8 | part of QA-010-T12 | report performance-perf012-2026-11-15T204424Z.json |
| `thresholds` | pass | 0.0 | QA-010-T12 | QA-010 overall pass |
| `xctest-materials` | pass | 50.1 | SHD-004-T20 | 5 tests, 0 failures, 0 skipped |
| `xctest-angle-layer` | pass | 13.5 | part of CMP-001-T20 | 7 tests, 0 failures, 0 skipped |
| `bench-shd002` | fail | 104.3 | SHD-002-T24 | no test summary in the log; exit 65; /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project ProjectM-DeviceTests.xcodeproj -scheme Devic / Build/qa-011/D2/20261115T204015Z/xcresult/bench-shd002.xcresult / Build/qa-011/D2/20261115T204015Z/xcresult/bench-shd002.xcresult |

## Artifacts

| Case | Path | Bytes | SHA-256 | Committed |
|---|---|---|---|---|
| `autorun-perf001` | `docs/test-reports/qa-011/runs/D2/20261115T204015Z/artifacts/automation-perf001-2026-11-15T204134Z.json` | 3181 | `90024c90b7a673c20a4eb67afbee71c93578557a7d0a8cd19b3454013b48c90c` | yes |
| `launches-sc015` | `docs/test-reports/qa-011/runs/D2/20261115T204015Z/artifacts/sc015.json` | 220 | `eb23b043ceb4fc035221c01bb9eef80fa448bbb8009536bc104cd4053f578296` | yes |
| `autorun-perf012` | `docs/test-reports/qa-011/runs/D2/20261115T204015Z/artifacts/performance-perf012-2026-11-15T204424Z.json` | 2504 | `4996b94ebe58400876a51bd89847e491fb13e81cce91d445a1e7e282afec1cf3` | yes |
| `thresholds` | `docs/test-reports/qa-011/runs/D2/20261115T204015Z/artifacts/performance-verdict.json` | 1757 | `85709a42b1b426f9af7c55f78d7b6b82d966f6f705413e9f2da8e96671e47231` | yes |
| `xctest-materials` | `Build/qa-011/D2/20261115T204015Z/logs/xctest-materials.log` | 3373236 | `cc78979a0cb6e15cfd350621b934806b9ef80e40a515cd35e90d80b4f048c35f` | no |
| `xctest-materials` | `Build/qa-011/D2/20261115T204015Z/xcresult/xctest-materials.xcresult` | 398309 | `24163ae1cb6ee9c66d9dcf097bd4f6ed627a23b59558a25d4bec5c54f6ceb816` | no |
| `xctest-angle-layer` | `Build/qa-011/D2/20261115T204015Z/logs/xctest-angle-layer.log` | 294792 | `bdf1f78e559f40505d46c0603667626f613e745ed926e7a7117b94cec1405521` | no |
| `xctest-angle-layer` | `Build/qa-011/D2/20261115T204015Z/xcresult/xctest-angle-layer.xcresult` | 53093 | `f93db77ffccd6ac1353966fd425a8f68a7d2f97563515486c0a7a755574a9b6d` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T204015Z/logs/bench-shd002.log` | 3255532 | `51082dbb212c624620bed52038a955274110d4bc5e3a58b5d2d1a082dd4b07bb` | no |
| `bench-shd002` | `Build/qa-011/D2/20261115T204015Z/xcresult/bench-shd002.xcresult` | 243354 | `277fe8c2c8891ece2654dd75abecbd731e50eb9410fb1dd90b854793c3c10808` | no |
