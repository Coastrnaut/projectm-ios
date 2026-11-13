# Autonomous roadmap run: status

- Run `cb545c51cf0b`, updated 2026-11-13T00:57:47Z; phase: **implementation**
- Roadmap SHA-256 `77a775e969de49fed946704fe966967cf8a87fa49090eefeaa834a4ee769da37` (frozen)
- Started from `419cc2a999edbc771333eb97968590802bc490fe`; integration branch `autonomous/integration` (local only, never pushed)
- Features: 326

## Counts by state

| State | Features |
|---|---|
| audited | 303 |
| implementing | 1 |
| integrated | 22 |

## Counts by priority

| Priority | audited | implementing | integrated |
|---|---|---|---|
| P0 | 66 | 1 | 20 |
| P1 | 149 | 0 | 2 |
| P2 | 79 | 0 | 0 |
| P3 | 9 | 0 | 0 |

## Final device gate

The physical-device suite may **not** start:
- 304 features are not implemented yet (first: ACC-001, ACC-002, ACC-003, ACC-004, ACC-005)

## Integrated

| ID | Feature | Merge commit | Branch |
|---|---|---|---|
| AUD-001 | Import DRM-free audio files | `a2813ab3fa4f` | `feature/aud-001` |
| AUD-002 | Support common audio containers | `f886b7ce7c76` | `feature/aud-002` |
| AUD-006 | Seekable transport | `03b23a8ae6a0` | `feature/aud-006` |
| AUD-014 | Audio session interruption recovery | `c4f03aa5e3d8` | `feature/aud-014` |
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
| PRE-015 | User preset duplication | `c6cce9988587` | `feature/pre-015` |

## Proved already implemented

None.

## Blocked or infeasible

None.

## Evidence by feature

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

### PRE-015 User preset duplication (integrated)
- `python3 scripts/check_compliance.py`: pass at `f4a06e68c3fe` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-015/20261112T194121/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `f4a06e68c3fe` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-015/20261112T194121/docs.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `f4a06e68c3fe` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/PRE-015/20261112T194121/swift-test_PresetLibrary.log`)
- `integration checkout, full preset library: xcodebuild projectM-iOS test on iPhone 17 iOS 27.2: projectM-iOSTests 108 pass; UI 24 pass (UserPresetEditing, UserPresets, PresetCollections, PresetLibrary, Purchase, Visualizer)`: pass at `41836f305bad` (log `.autonomous/logs/integration/pre-015/app-tests.log`)
