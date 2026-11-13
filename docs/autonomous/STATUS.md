# Autonomous roadmap run: status

- Run `cb545c51cf0b`, updated 2026-11-13T11:29:14Z; phase: **implementation**
- Roadmap SHA-256 `77a775e969de49fed946704fe966967cf8a87fa49090eefeaa834a4ee769da37` (frozen)
- Started from `419cc2a999edbc771333eb97968590802bc490fe`; integration branch `autonomous/integration` (local only, never pushed)
- Features: 326

## Counts by state

| State | Features |
|---|---|
| audited | 298 |
| unit_passed | 1 |
| integrated | 26 |
| skipped_existing | 1 |

## Counts by priority

| Priority | audited | unit_passed | integrated | skipped_existing |
|---|---|---|---|---|
| P0 | 63 | 1 | 22 | 1 |
| P1 | 147 | 0 | 4 | 0 |
| P2 | 79 | 0 | 0 | 0 |
| P3 | 9 | 0 | 0 | 0 |

## Final device gate

The physical-device suite may **not** start:
- 299 features are not implemented yet (first: ACC-001, ACC-002, ACC-003, ACC-004, ACC-005)

## Integrated

| ID | Feature | Merge commit | Branch |
|---|---|---|---|
| AUD-001 | Import DRM-free audio files | `a2813ab3fa4f` | `feature/aud-001` |
| AUD-002 | Support common audio containers | `f886b7ce7c76` | `feature/aud-002` |
| AUD-003 | Audio library queue | `c06876d434a3` | `feature/aud-003` |
| AUD-006 | Seekable transport | `03b23a8ae6a0` | `feature/aud-006` |
| AUD-014 | Audio session interruption recovery | `c4f03aa5e3d8` | `feature/aud-014` |
| AUD-016 | Reference tone suite | `f69525cf0e8d` | `feature/aud-016` |
| AUTO-001 | Roadmap parser | `419cc2a999ed` | `autonomous/integration` |
| AUTO-002 | Implementation inventory gate | `419cc2a999ed` | `autonomous/integration` |
| AUTO-003 | Dependency scheduler | `419cc2a999ed` | `autonomous/integration` |
| AUTO-004 | Worktree isolation | `419cc2a999ed` | `autonomous/integration` |
| AUTO-005 | Spec Kit generation driver | `419cc2a999ed` | `autonomous/integration` |
| AUTO-006 | Autonomous ambiguity resolution | `419cc2a999ed` | `autonomous/integration` |
| AUTO-007 | Headless Claude execution | `419cc2a999ed` | `autonomous/integration` |
| AUTO-008 | Compile-and-unit gate | `419cc2a999ed` | `autonomous/integration` |
| AUTO-009 | Bounded remediation loop | `419cc2a999ed` | `autonomous/integration` |
| AUTO-010 | State checkpointing | `419cc2a999ed` | `autonomous/integration` |
| AUTO-011 | Merge conflict arbiter | `419cc2a999ed` | `autonomous/integration` |
| AUTO-012 | Progress dashboard | `419cc2a999ed` | `autonomous/integration` |
| AUTO-013 | Final device-test gate | `419cc2a999ed` | `autonomous/integration` |
| AUTO-014 | Unattended safety budget | `419cc2a999ed` | `autonomous/integration` |
| PERF-011 | Background resource release | `6d669fcb8576` | `feature/perf-011` |
| PRE-007 | Preset collections | `e834535cb98b` | `feature/pre-007` |
| PRE-012 | Preset import validation | `4bf9f50d1af8` | `feature/pre-012` |
| PRE-014 | Bulk preset export | `a20ba4bafb5e` | `feature/pre-014` |
| PRE-015 | User preset duplication | `c6cce9988587` | `feature/pre-015` |
| QA-007 | Audio source contract suite | `32172fdd5795` | `feature/qa-007` |

## Proved already implemented

- **QA-001** Deterministic PCM fixtures: code Packages/AudioCore/Sources/AudioCore/ReferenceTones/ReferenceToneCatalog.swift (catalog version 1, 10 fixtures, expected FFT bins, onsets, tempo, sweep frequencies), Packages/AudioCore/Sources/AudioCore/ReferenceTones/ToneGenerator.swift and ToneMath.swift (frame-index generator, own sin/exp/log), specs/011-aud-016-reference-tone-suite/contracts/fixture-catalog.md (38 golden SHA-256 values); tests ReferenceToneCatalogTests.testGoldenHashesOnRepeatedRuns and ReferenceToneOracleTests passed on Linux in CI run 43349673457, job 131638159151 (commit 073f92c), same suites passed on the macOS host and the iOS 27.2 simulator in the AUD-016 gates and post-merge run (.autonomous/logs/integration/aud-016/), scripts/check_reference_tone_goldens.py: independent CPython port reproduces 18 mono hashes (test_scripts.py)

## Blocked or infeasible

None.

## Evidence by feature

### ANL-001 Windowed FFT (unit_passed)
- `python3 scripts/check_compliance.py`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=62BA098B-4CBB-4DB6-91AD-51494936CF89 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_AnalysisFeatures.log`)
- `swift test --package-path Packages/AudioCore`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_AudioCore.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_CaptureUI.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_Diagnostics.log`)
- `xcodebuild -scheme Rendering-Package -destination id=62BA098B-4CBB-4DB6-91AD-51494936CF89 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/sim-test_Rendering.log`)

### AUD-001 Import DRM-free audio files (integrated)
- `python3 scripts/check_compliance.py`: pass at `d9a60b2a6692` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153538/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `d9a60b2a6692` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153538/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `d9a60b2a6692` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153538/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `d9a60b2a6692` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153538/autonomous-tests.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `d9a60b2a6692` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153538/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `d9a60b2a6692` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153538/swift-test_CaptureUI.log`)
- `python3 scripts/check_compliance.py`: pass at `3051b5f72a55` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153606/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `3051b5f72a55` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153606/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `3051b5f72a55` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153606/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `3051b5f72a55` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153606/autonomous-tests.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `3051b5f72a55` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153606/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `3051b5f72a55` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-001/20261112T153606/swift-test_CaptureUI.log`)
- `integration checkout: xcodegen generate; xcodebuild -scheme projectM-iOS -destination id=4E32B01D (iPhone 17, iOS 27.2) test: projectM-iOSTests 66 pass, ImportedAudioUITests 4 pass, StatusUITests 7 pass`: pass at `a2813ab3fa4f` (log `.autonomous/logs/integration/aud-001/app-tests.log`)

### AUD-002 Support common audio containers (integrated)
- `python3 scripts/check_compliance.py`: pass at `4700a64a37aa` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-002/20261112T161949/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `4700a64a37aa` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-002/20261112T161949/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `4700a64a37aa` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-002/20261112T161949/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `4700a64a37aa` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-002/20261112T161949/autonomous-tests.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `4700a64a37aa` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-002/20261112T161949/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `4700a64a37aa` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-002/20261112T161949/swift-test_CaptureUI.log`)
- `integration checkout: xcodegen generate; xcodebuild -scheme projectM-iOS -destination id=4E32B01D (iPhone 17, iOS 27.2) test: projectM-iOSTests, ImportedAudioUITests (5)`: pass at `f886b7ce7c76` (log `.autonomous/logs/integration/aud-002/app-tests.log`)

### AUD-003 Audio library queue (integrated)
- `python3 scripts/check_compliance.py`: pass at `6412b1087980` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-003/20261113T060308/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `6412b1087980` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-003/20261113T060308/docs.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `6412b1087980` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-003/20261113T060308/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `6412b1087980` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-003/20261113T060308/swift-test_CaptureUI.log`)
- `integration checkout, full preset library: CaptureKit 355 on iOS 27.2 sim; xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 126 pass; UI 20 pass (PlayQueue, ImportedAudio, Transport, Interruption, Status)`: pass at `1d4d4b9` (log `.autonomous/logs/integration/aud-003/app-tests.log`)

### AUD-006 Seekable transport (integrated)
- `python3 scripts/check_compliance.py`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/autonomous-tests.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/AudioCore`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/swift-test_AudioCore.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/swift-test_CaptureUI.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/swift-test_Diagnostics.log`)
- `xcodebuild -scheme Rendering-Package -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `383d9ab633a4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-006/20261112T174904/sim-test_Rendering.log`)
- `integration checkout, full preset library: xcodebuild -scheme projectM-iOS -destination id=4E32B01D (iPhone 17, iOS 27.2) test: projectM-iOSTests 87 pass; UI tests 22 pass (Transport 3, ImportedAudio 5, Status 7, Visualizer 7)`: pass at `e40e5780bb27` (log `.autonomous/logs/integration/aud-006/app-tests.log`)

### AUD-014 Audio session interruption recovery (integrated)
- `python3 scripts/check_compliance.py`: pass at `8d270f3cbeed` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-014/20261112T185431/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `8d270f3cbeed` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-014/20261112T185431/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `8d270f3cbeed` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-014/20261112T185431/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `8d270f3cbeed` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-014/20261112T185431/autonomous-tests.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `8d270f3cbeed` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-014/20261112T185431/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `8d270f3cbeed` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-014/20261112T185431/swift-test_CaptureUI.log`)
- `integration checkout, full preset library: xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 102 pass; UI 25 pass (Interruption, Transport, ImportedAudio, Status, Visualizer)`: pass at `b96d30cfbd82` (log `.autonomous/logs/integration/aud-014/app-tests.log`)

### AUD-016 Reference tone suite (integrated)
- `python3 scripts/check_compliance.py`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/autonomous-tests.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/AudioCore`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/swift-test_AudioCore.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/swift-test_CaptureUI.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/swift-test_Diagnostics.log`)
- `xcodebuild -scheme Rendering-Package -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `a7e38976d177` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-016/20261112T202048/sim-test_Rendering.log`)
- `integration checkout, full preset library: CaptureKit 287 host / 291 iOS 27.2 sim; xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 111 pass; UI 25 pass (TestSignals, Interruption, Transport, ImportedAudio, Status, Settings)`: pass at `25617b630dbb` (log `.autonomous/logs/integration/aud-016/app-tests.log`)

### AUTO-001 Roadmap parser (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-002 Implementation inventory gate (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-003 Dependency scheduler (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-004 Worktree isolation (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-005 Spec Kit generation driver (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-006 Autonomous ambiguity resolution (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-007 Headless Claude execution (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-008 Compile-and-unit gate (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-009 Bounded remediation loop (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-010 State checkpointing (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-011 Merge conflict arbiter (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-012 Progress dashboard (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-013 Final device-test gate (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### AUTO-014 Unattended safety budget (integrated)
- `python3 scripts/autonomous/tests/test_autonomous.py (48 tests)`: pass at `419cc2a999ed`

### PERF-011 Background resource release (integrated)
- `python3 scripts/check_compliance.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151252/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151252/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151252/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151252/autonomous-tests.log`)
- `swift test --package-path Packages/ANGLERendering`: exit 1 at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151252/swift-test_ANGLERendering.log`)
- `python3 scripts/check_compliance.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151339/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151339/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151339/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151339/autonomous-tests.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: exit 65 at `e463058b1c92` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T151339/sim-test_ANGLERendering.log`)
- `python3 scripts/check_compliance.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/autonomous-tests.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/swift-test_Diagnostics.log`)
- `swift test --package-path Packages/PresentationLifecycle`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/swift-test_PresentationLifecycle.log`)
- `xcodebuild -scheme Rendering-Package -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: exit 65 at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152418/sim-test_Rendering.log`)
- `python3 scripts/check_compliance.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/autonomous-tests.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/swift-test_Diagnostics.log`)
- `swift test --package-path Packages/PresentationLifecycle`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/swift-test_PresentationLifecycle.log`)
- `xcodebuild -scheme Rendering-Package -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `685f31acc792` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PERF-011/20261112T152635/sim-test_Rendering.log`)
- `integration checkout: xcodegen generate; xcodebuild -scheme projectM-iOS -destination id=4E32B01D (iPhone 17, iOS 27.2) -only-testing:projectM-iOSTests test`: pass at `6d669fcb8576` (log `.autonomous/logs/integration/perf-011/app-unit-tests.log`)

### PRE-007 Preset collections (integrated)
- `python3 scripts/check_compliance.py`: pass at `20a56625dc20` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-007/20261112T163454/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `20a56625dc20` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-007/20261112T163454/docs.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `20a56625dc20` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-007/20261112T163454/swift-test_PresetLibrary.log`)
- `python3 scripts/check_compliance.py`: pass at `c9aefe517159` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-007/20261112T163519/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `c9aefe517159` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-007/20261112T163519/docs.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `c9aefe517159` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-007/20261112T163519/swift-test_PresetLibrary.log`)
- `integration checkout, full preset library: xcodebuild -scheme projectM-iOS -destination id=4E32B01D (iPhone 17, iOS 27.2) test: projectM-iOSTests 84 pass; UI tests 16 pass (PresetCollections 3, PresetLibrary, Purchase, ImportedAudio)`: pass at `e834535cb98b` (log `.autonomous/logs/integration/pre-007/app-tests.log`)

### PRE-012 Preset import validation (integrated)
- `python3 scripts/check_compliance.py`: pass at `6d4ada96b86c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-012/20261112T182006/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `6d4ada96b86c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-012/20261112T182006/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `6d4ada96b86c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-012/20261112T182006/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `6d4ada96b86c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-012/20261112T182006/swift-test_PresetLibrary.log`)
- `xcodebuild -scheme Rendering-Package -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `6d4ada96b86c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-012/20261112T182006/sim-test_Rendering.log`)
- `integration checkout, full packs: PRE012_CORPUS swift test PresetLibrary 133 pass (14576 pack files, 0 over a limit, 2 incompleteShader); xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: unit and UI suites pass (UserPresets 2, PresetCollections 3, PresetLibrary, Purchase, Visualizer); PresetBlocklist.json in the app bundle`: pass at `9e78b94c8ee1` (log `.autonomous/logs/integration/pre-012/app-tests.log`)

### PRE-014 Bulk preset export (integrated)
- `python3 scripts/check_compliance.py`: pass at `10193f697212` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-014/20261112T205210/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `10193f697212` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-014/20261112T205210/docs.log`)
- `swift test --package-path Packages/LocalPortability`: pass at `10193f697212` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-014/20261112T205210/swift-test_LocalPortability.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `10193f697212` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-014/20261112T205210/swift-test_PresetLibrary.log`)
- `integration checkout, full preset library: LocalPortability 51 on iOS 27.2 sim; xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 119 pass; UI 16 pass (UserPresetExport, UserPresetEditing, UserPresets, PresetLibrary, Purchase)`: pass at `623a76c85396` (log `.autonomous/logs/integration/pre-014/app-tests.log`)

### PRE-015 User preset duplication (integrated)
- `python3 scripts/check_compliance.py`: pass at `f4a06e68c3fe` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-015/20261112T194121/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `f4a06e68c3fe` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-015/20261112T194121/docs.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `f4a06e68c3fe` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-015/20261112T194121/swift-test_PresetLibrary.log`)
- `integration checkout, full preset library: xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 108 pass; UI 24 pass (UserPresetEditing, UserPresets, PresetCollections, PresetLibrary, Purchase, Visualizer)`: pass at `41836f305bad` (log `.autonomous/logs/integration/pre-015/app-tests.log`)

### QA-007 Audio source contract suite (integrated)
- `python3 scripts/check_compliance.py`: pass at `1985f0c1e666` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/QA-007/20261112T210720/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `1985f0c1e666` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/QA-007/20261112T210720/docs.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `1985f0c1e666` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/QA-007/20261112T210720/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `1985f0c1e666` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/QA-007/20261112T210720/swift-test_CaptureUI.log`)
- `integration checkout: CaptureKit 309 on iOS 27.2 sim; xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 119 pass; UI 22 pass (Interruption, Status, Transport, ImportedAudio, TestSignals)`: pass at `df432e31de46` (log `.autonomous/logs/integration/qa-007/app-tests.log`)
