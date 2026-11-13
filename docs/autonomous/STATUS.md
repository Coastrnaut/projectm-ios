# Autonomous roadmap run: status

- Run `cb545c51cf0b`, updated 2026-11-13T17:07:54Z; phase: **implementation**
- Roadmap SHA-256 `77a775e969de49fed946704fe966967cf8a87fa49090eefeaa834a4ee769da37` (frozen)
- Started from `419cc2a999edbc771333eb97968590802bc490fe`; integration branch `autonomous/integration` (local only, never pushed)
- Features: 326

## Counts by state

| State | Features |
|---|---|
| audited | 274 |
| integrated | 51 |
| skipped_existing | 1 |

## Counts by priority

| Priority | audited | integrated | skipped_existing |
|---|---|---|---|
| P0 | 47 | 39 | 1 |
| P1 | 139 | 12 | 0 |
| P2 | 79 | 0 | 0 |
| P3 | 9 | 0 | 0 |

## Final device gate

The physical-device suite may **not** start:
- 274 features are not implemented yet (first: ACC-001, ACC-003, ACC-004, ACC-005, ACC-006)

## Integrated

| ID | Feature | Merge commit | Branch |
|---|---|---|---|
| ACC-002 | Reduced flash preset policy | `61c926cb8b59` | `feature/acc-002` |
| ANL-001 | Windowed FFT | `df16f2b90397` | `feature/anl-001` |
| ANL-002 | Log-frequency bands | `493269c77462` | `feature/anl-002` |
| ANL-004 | Spectral flux onset detector | `e1ae49c81d34` | `feature/anl-004` |
| ANL-005 | Adaptive beat tracker | `18a7b93483d6` | `feature/anl-005` |
| ANL-016 | Analysis event bus | `97e498d64a14` | `feature/anl-016` |
| AUD-001 | Import DRM-free audio files | `a2813ab3fa4f` | `feature/aud-001` |
| AUD-002 | Support common audio containers | `f886b7ce7c76` | `feature/aud-002` |
| AUD-003 | Audio library queue | `c06876d434a3` | `feature/aud-003` |
| AUD-004 | Loop track and queue | `8d96030954ff` | `feature/aud-004` |
| AUD-005 | Shuffle with history | `bf010e1ee1e6` | `None` |
| AUD-006 | Seekable transport | `03b23a8ae6a0` | `feature/aud-006` |
| AUD-007 | Audio output route indicator | `902d1734d42a` | `feature/aud-007` |
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
| CAM-001 | Rear camera layer | `05ef3cb4e24b` | `feature/cam-001` |
| CAM-012 | Camera privacy status | `a188b049fc60` | `feature/cam-012` |
| CMP-001 | Unified layer protocol | `ba60b9d3485a` | `feature/cmp-001` |
| FX-001 | Bloom | `1192e0d6503e` | `feature/fx-001` |
| FX-019 | Strobe safety envelope | `6cfcbaabc8d0` | `feature/fx-019` |
| MOD-001 | Typed parameter registry | `304f3bce431a` | `feature/mod-001` |
| MOD-002 | Audio feature binding | `006678f3d7a5` | `feature/mod-002` |
| MOD-003 | Linear mapping | `29cd3bbb1e12` | `feature/mod-003` |
| MOD-014 | Modulation feedback prevention | `3b3a60649025` | `feature/mod-014` |
| OSC-001 | OSC receiver | `13d9883531b9` | `feature/osc-001` |
| OSC-002 | OSC message parser | `3b3a60649025` | `feature/osc-002` |
| OSC-007 | OSC network access switch | `ade4dfec39a5` | `feature/osc-007` |
| PERF-011 | Background resource release | `6d669fcb8576` | `feature/perf-011` |
| PRE-007 | Preset collections | `e834535cb98b` | `feature/pre-007` |
| PRE-012 | Preset import validation | `4bf9f50d1af8` | `feature/pre-012` |
| PRE-014 | Bulk preset export | `a20ba4bafb5e` | `feature/pre-014` |
| PRE-015 | User preset duplication | `c6cce9988587` | `feature/pre-015` |
| QA-007 | Audio source contract suite | `32172fdd5795` | `feature/qa-007` |
| SHD-001 | Procedural material catalog | `ade4dfec39a5` | `feature/shd-001` |
| SHOW-011 | Tap tempo | `11329d52e6dc` | `feature/show-011` |
| VIS-001 | Circular spectrum | `48285d49c422` | `feature/vis-001` |
| VIS-002 | Linear spectrum | `c2b2f75c11bb` | `feature/vis-002` |

## Proved already implemented

- **QA-001** Deterministic PCM fixtures: code Packages/AudioCore/Sources/AudioCore/ReferenceTones/ReferenceToneCatalog.swift (catalog version 1, 10 fixtures, expected FFT bins, onsets, tempo, sweep frequencies), Packages/AudioCore/Sources/AudioCore/ReferenceTones/ToneGenerator.swift and ToneMath.swift (frame-index generator, own sin/exp/log), specs/011-aud-016-reference-tone-suite/contracts/fixture-catalog.md (38 golden SHA-256 values); tests ReferenceToneCatalogTests.testGoldenHashesOnRepeatedRuns (split on 2026-11-13 into testGoldenHashesOnRepeatedRuns44100 and ...48000, plus testGoldenTableCoversEveryVariant; all 38 golden values still checked) and ReferenceToneOracleTests passed on Linux in CI run 43349673457, job 131638159151 (commit 073f92c), same suites passed on the macOS host and the iOS 27.2 simulator in the AUD-016 gates and post-merge run (.autonomous/logs/integration/aud-016/), scripts/check_reference_tone_goldens.py: independent CPython port reproduces 18 mono hashes (test_scripts.py)

## Blocked or infeasible

None.

## Evidence by feature

### ACC-002 Reduced flash preset policy (integrated)
- `python3 scripts/check_compliance.py`: pass at `64829437c98c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ACC-002/20261113T111136/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `64829437c98c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ACC-002/20261113T111136/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `64829437c98c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ACC-002/20261113T111136/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `64829437c98c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ACC-002/20261113T111136/autonomous-tests.log`)
- `swift test --package-path Packages/PresetLibrary`: pass at `64829437c98c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ACC-002/20261113T111136/swift-test_PresetLibrary.log`)
- `post-merge (main checkout, packs present): projectM-iOSTests 157 incl. FlashPolicyTests and PresetTests full-library scope, FlashPolicyUITests 14.8 s, SettingsUITests reduce flashing 15.5 s on iPhone 17 iOS 27.2 sim`: pass at `61c926cb8b59` (log `.autonomous/logs/integration/acc-002/app-tests.log`)
- `post-merge: PresetLibrary xcodebuild test on iPhone 17 sim (201, 1 skipped)`: pass at `61c926cb8b59` (log `.autonomous/logs/integration/acc-002/presetlibrary-sim.log`)

### ANL-001 Windowed FFT (integrated)
- `python3 scripts/check_compliance.py`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=62BA098B-4CBB-4DB6-91AD-51494936CF89 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_AnalysisFeatures.log`)
- `swift test --package-path Packages/AudioCore`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_AudioCore.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_CaptureUI.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/swift-test_Diagnostics.log`)
- `xcodebuild -scheme Rendering-Package -destination id=62BA098B-4CBB-4DB6-91AD-51494936CF89 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `0d0eb4b9f656` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-001/20261113T061117/sim-test_Rendering.log`)
- `integration checkout: AnalysisFeatures 28 and AudioCore 125 on iOS 27.2 sim; app: projectM-iOSTests 126 pass after the LibraryStore fix, TestSignals and Status UI pass; PurchaseUITests 3 pass`: pass at `e6cd73d5f648` (log `.autonomous/logs/integration/librarystore-fix/app-tests.log`)

### ANL-002 Log-frequency bands (integrated)
- `python3 scripts/check_compliance.py`: pass at `bf549085819b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-002/20261113T071424/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `bf549085819b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-002/20261113T071424/docs.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `bf549085819b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-002/20261113T071424/swift-test_AnalysisFeatures.log`)
- `integration checkout: AnalysisFeatures 46 on iOS 27.2 sim; 46 (1 skipped) with -DANALYSIS_NO_ACCELERATE on the host; 0 PosterBoard reports`: pass at `493269c` (log `.autonomous/logs/integration/anl-002/analysis-sim.log`)

### ANL-004 Spectral flux onset detector (integrated)
- `python3 scripts/check_compliance.py`: pass at `e1aeb82495a0` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-004/20261113T082643/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `e1aeb82495a0` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-004/20261113T082643/docs.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `e1aeb82495a0` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-004/20261113T082643/swift-test_AnalysisFeatures.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `e1aeb82495a0` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-004/20261113T082643/swift-test_VisualGenerators.log`)
- `integration checkout: AnalysisFeatures 73 on iOS 27.2 sim (213 s) and 73 (1 skipped) with -DANALYSIS_NO_ACCELERATE (318 s); VisualGenerators 40 on sim; app: projectM-iOSTests 131, NativeVisualUITests 4 pass; 0 PosterBoard reports`: pass at `e1ae49c` (log `.autonomous/logs/integration/anl-004/app-tests.log`)

### ANL-005 Adaptive beat tracker (integrated)
- `python3 scripts/check_compliance.py`: pass at `cff52d8eb33b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-005/20261113T094159/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `cff52d8eb33b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-005/20261113T094159/docs.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `cff52d8eb33b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-005/20261113T094159/swift-test_AnalysisFeatures.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `cff52d8eb33b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-005/20261113T094159/swift-test_VisualGenerators.log`)
- `integration checkout: AnalysisFeatures 91 on iOS 27.2 sim in 34 s; 91 (1 skipped) with -DANALYSIS_NO_ACCELERATE in 50 s; test-speed UI run with the full library 11/11 in 235 s; 0 PosterBoard reports`: pass at `18a7b93` (log `.autonomous/logs/integration/anl-005/analysis-sim.log`)

### ANL-016 Analysis event bus (integrated)
- `python3 scripts/check_compliance.py`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101323/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101323/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: exit 65 at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101323/sim-test_ANGLERendering.log`)
- `python3 scripts/check_compliance.py`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/swift-test_AnalysisFeatures.log`)
- `swift test --package-path Packages/AudioCore`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/swift-test_AudioCore.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/swift-test_CaptureUI.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/swift-test_Diagnostics.log`)
- `xcodebuild -scheme Rendering-Package -destination id=4E32B01D-7911-4A64-A944-877DDD445BC0 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/sim-test_Rendering.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `1e9e7eec69b8` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/ANL-016/20261113T101505/swift-test_VisualGenerators.log`)
- `integration checkout: AnalysisFeatures 106 on iOS 27.2 sim; app: projectM-iOSTests 133; NativeVisualUITests 3 of 4 (fallback test fails in openSettings, a test-helper race; fix pending from the test pass)`: exit 1 at `97e498d` (log `.autonomous/logs/integration/anl-016/app-tests.log`)
- `integration checkout after the NativeVisualUITests fix (facfd46): NativeVisualUITests 4/4 (fallback test 13.2 s), 79 s wall; agent's 5 runs 20/20`: pass at `facfd46` (log `.autonomous/logs/integration/flaky-fix/ui.log`)

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

### AUD-004 Loop track and queue (integrated)
- `python3 scripts/check_compliance.py`: pass at `489f122c1431` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-004/20261113T071949/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `489f122c1431` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-004/20261113T071949/docs.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `489f122c1431` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-004/20261113T071949/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `489f122c1431` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-004/20261113T071949/swift-test_CaptureUI.log`)
- `integration checkout: CaptureKit 395 on iOS 27.2 sim; xcodebuild projectM-iOS test: projectM-iOSTests 126 pass; UI 15 pass (RepeatMode, PlayQueue, Transport, ImportedAudio, Interruption); 0 PosterBoard reports`: pass at `8d96030` (log `.autonomous/logs/integration/aud-004/app-tests.log`)

### AUD-005 Shuffle with history (integrated)
- `python3 scripts/check_compliance.py`: pass at `8b729cdfa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-005/20261113T101054/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `8b729cdfa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-005/20261113T101054/docs.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `8b729cdfa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-005/20261113T101054/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `8b729cdfa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-005/20261113T101054/swift-test_CaptureUI.log`)

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

### AUD-007 Audio output route indicator (integrated)
- `python3 scripts/check_compliance.py`: pass at `6fdff3fc48ef` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-007/20261113T103522/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `6fdff3fc48ef` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-007/20261113T103522/docs.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `6fdff3fc48ef` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-007/20261113T103522/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `6fdff3fc48ef` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/AUD-007/20261113T103522/swift-test_CaptureUI.log`)
- `integration checkout (after the VisualizerView merge with VIS-002): CaptureKit 449 on iOS 27.2 sim; app: projectM-iOSTests 140; UI 9 (RouteIndicator, Status, LinearSpectrum); 239 s wall; 0 PosterBoard reports`: pass at `902d173` (log `.autonomous/logs/integration/aud-007/app-tests.log`)

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

### CAM-001 Rear camera layer (integrated)
- `python3 scripts/check_compliance.py`: pass at `88b2544a2588` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CAM-001/20261113T113607/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `88b2544a2588` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CAM-001/20261113T113607/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `88b2544a2588` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CAM-001/20261113T113607/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Compositor`: pass at `88b2544a2588` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CAM-001/20261113T113607/swift-test_Compositor.log`)
- `post-merge (with the VIS-002-F1 picker rows): projectM-iOSTests 172 incl. CameraVisualTests, CameraUITests 2 (10.0 s, 11.2 s), NativeVisual 4, Glow 2, LinearSpectrum 1, OSC 1 UI tests on iPhone 17 iOS 27.2 sim; SettingsUITests 4 pass after the scroll fix`: pass at `05ef3cb4e24b` (log `.autonomous/logs/integration/cam-001/app-tests.log`)
- `post-merge: Compositor xcodebuild test on iPhone 17 sim (61)`: pass at `05ef3cb4e24b` (log `.autonomous/logs/integration/cam-001/compositor-sim.log`)

### CAM-012 Camera privacy status (integrated)
- `python3 scripts/check_compliance.py`: pass at `3e408a740a3b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CAM-012/20261113T120140/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `3e408a740a3b` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CAM-012/20261113T120140/docs.log`)
- `post-merge: projectM-iOSTests 179 incl. CameraPrivacyStatusTests, CameraPrivacyStatusUITests 14.8 s, CameraUITests 2 (11.0 s, 11.4 s) on iPhone 17 iOS 27.2 sim`: pass at `a188b049fc60` (log `.autonomous/logs/integration/cam-012/app-tests.log`)

### CMP-001 Unified layer protocol (integrated)
- `python3 scripts/check_compliance.py`: pass at `19d1bd7e65a2` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CMP-001/20261113T110629/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `19d1bd7e65a2` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CMP-001/20261113T110629/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `19d1bd7e65a2` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CMP-001/20261113T110629/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Compositor`: pass at `19d1bd7e65a2` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/CMP-001/20261113T110629/swift-test_Compositor.log`)
- `post-merge: projectM-iOSTests 147 on iPhone 17 iOS 27.2 sim (app links the changed ANGLERendering)`: pass at `ba60b9d3485a` (log `.autonomous/logs/integration/cmp-001/app-tests.log`)
- `post-merge: Compositor xcodebuild test on iPhone 17 sim (43)`: pass at `ba60b9d3485a` (log `.autonomous/logs/integration/cmp-001/compositor-sim.log`)
- `post-merge: Compositor Linux shape on host, -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE (21)`: pass at `ba60b9d3485a` (log `.autonomous/logs/integration/cmp-001/compositor-linuxshape.log`)

### FX-001 Bloom (integrated)
- `python3 scripts/check_compliance.py`: pass at `94f4b3a6b7c3` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-001/20261113T090348/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `94f4b3a6b7c3` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-001/20261113T090348/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `94f4b3a6b7c3` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-001/20261113T090348/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `94f4b3a6b7c3` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-001/20261113T090348/autonomous-tests.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `94f4b3a6b7c3` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-001/20261113T090348/swift-test_VisualGenerators.log`)
- `integration checkout: VisualGenerators 76 on iOS 27.2 sim (GPU tests ran) and 59 with -DVISUAL_NO_METAL; app: projectM-iOSTests 133 pass, UI 16 pass (Glow, NativeVisual, Settings, Visualizer); 0 PosterBoard reports`: pass at `1192e0d` (log `.autonomous/logs/integration/fx-001/app-tests.log`)

### FX-019 Strobe safety envelope (integrated)
- `python3 scripts/check_compliance.py`: pass at `bc80d4775650` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-019/20261113T095545/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `bc80d4775650` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-019/20261113T095545/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=77E17861-E687-4274-8A84-14224F32BE3E CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `bc80d4775650` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-019/20261113T095545/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/FlashSafety`: pass at `bc80d4775650` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-019/20261113T095545/swift-test_FlashSafety.log`)
- `xcodebuild -scheme Rendering-Package -destination id=77E17861-E687-4274-8A84-14224F32BE3E CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `bc80d4775650` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-019/20261113T095545/sim-test_Rendering.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `bc80d4775650` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/FX-019/20261113T095545/swift-test_VisualGenerators.log`)
- `integration checkout: VisualGenerators 81 on iOS 27.2 sim, 63 with -DVISUAL_NO_METAL; FlashSafety 20; app: projectM-iOSTests 133, UI 11 (NativeVisual, Visualizer); 211 s wall; 0 PosterBoard reports`: pass at `6cfcbaa` (log `.autonomous/logs/integration/fx-019/app-tests.log`)

### MOD-001 Typed parameter registry (integrated)
- `python3 scripts/check_compliance.py`: pass at `c62c162f633a` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-001/20261113T104902/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `c62c162f633a` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-001/20261113T104902/docs.log`)
- `swift test --package-path Packages/ParameterGraph`: pass at `c62c162f633a` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-001/20261113T104902/swift-test_ParameterGraph.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `c62c162f633a` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-001/20261113T104902/swift-test_VisualGenerators.log`)
- `post-merge: projectM-iOSTests 147 incl. ParameterCatalogAppTests on iPhone 17 iOS 27.2 sim`: pass at `304f3bce431a` (log `.autonomous/logs/integration/mod-001/app-tests.log`)
- `post-merge: ParameterGraph xcodebuild test on iPhone 17 sim (26)`: pass at `304f3bce431a` (log `.autonomous/logs/integration/mod-001/pg-sim.log`)
- `post-merge: VisualGenerators xcodebuild test on iPhone 17 sim (100)`: pass at `304f3bce431a` (log `.autonomous/logs/integration/mod-001/vg-sim.log`)

### MOD-002 Audio feature binding (integrated)
- `python3 scripts/check_compliance.py`: pass at `65676d7730a5` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-002/20261113T111554/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `65676d7730a5` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-002/20261113T111554/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `65676d7730a5` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-002/20261113T111554/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Compositor`: pass at `65676d7730a5` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-002/20261113T111554/swift-test_Compositor.log`)
- `swift test --package-path Packages/ParameterGraph`: pass at `65676d7730a5` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-002/20261113T111554/swift-test_ParameterGraph.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `65676d7730a5` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-002/20261113T111554/swift-test_VisualGenerators.log`)
- `post-merge: projectM-iOSTests 159, AudioFeatureBindingUITests 13.8 s, GlowUITests 2 (11.6 s, 20.6 s) on iPhone 17 iOS 27.2 sim`: pass at `006678f3d7a5` (log `.autonomous/logs/integration/mod-002/app-tests.log`)
- `post-merge: ParameterGraph xcodebuild test on iPhone 17 sim (42)`: pass at `006678f3d7a5` (log `.autonomous/logs/integration/mod-002/pg-sim.log`)
- `post-merge: VisualGenerators xcodebuild test on iPhone 17 sim (103)`: pass at `006678f3d7a5` (log `.autonomous/logs/integration/mod-002/vg-sim.log`)

### MOD-003 Linear mapping (integrated)
- `python3 scripts/check_compliance.py`: pass at `8d9618afc5c4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-003/20261113T112510/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `8d9618afc5c4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-003/20261113T112510/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `8d9618afc5c4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-003/20261113T112510/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Compositor`: pass at `8d9618afc5c4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-003/20261113T112510/swift-test_Compositor.log`)
- `swift test --package-path Packages/ParameterGraph`: pass at `8d9618afc5c4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-003/20261113T112510/swift-test_ParameterGraph.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `8d9618afc5c4` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-003/20261113T112510/swift-test_VisualGenerators.log`)
- `post-merge: projectM-iOSTests 159 + AudioFeatureBindingUITests 13.8 s on iPhone 17 iOS 27.2 sim`: pass at `29cd3bbb1e12` (log `.autonomous/logs/integration/mod-003/app-tests.log`)
- `post-merge: ParameterGraph xcodebuild test on iPhone 17 sim (48)`: pass at `29cd3bbb1e12` (log `.autonomous/logs/integration/mod-003/pg-sim.log`)

### MOD-014 Modulation feedback prevention (integrated)
- `python3 scripts/check_compliance.py`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Compositor`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/swift-test_Compositor.log`)
- `swift test --package-path Packages/ParameterGraph`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/swift-test_ParameterGraph.log`)
- `swift test --package-path Packages/PerformanceControl`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/swift-test_PerformanceControl.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `a08446ecdde1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/MOD-014/20261113T114626/swift-test_VisualGenerators.log`)
- `post-merge: ParameterGraph xcodebuild test on iPhone 17 sim (66); projectM-iOSTests 172 + AudioFeatureBindingUITests 13.7 s`: pass at `3b3a60649025` (log `.autonomous/logs/integration/mod-014-osc-002/pg-sim.log`)

### OSC-001 OSC receiver (integrated)
- `python3 scripts/check_compliance.py`: pass at `6467d622b4bc` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-001/20261113T113140/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `6467d622b4bc` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-001/20261113T113140/docs.log`)
- `swift test --package-path Packages/PerformanceControl`: pass at `6467d622b4bc` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-001/20261113T113140/swift-test_PerformanceControl.log`)
- `post-merge: projectM-iOSTests 165 + OSCReceiverUITests 12.5 s on iPhone 17 iOS 27.2 sim (SettingsUITests licenses fixed in the next commit, all 4 pass)`: pass at `13d9883531b9` (log `.autonomous/logs/integration/osc-001/app-tests.log`)
- `post-merge: PerformanceControl xcodebuild test on iPhone 17 sim (58, incl. loopback acceptance)`: pass at `13d9883531b9` (log `.autonomous/logs/integration/osc-001/perf-sim.log`)
- `post-merge: SettingsUITests 4 pass after scrolling to Licenses (9.3-20.1 s)`: pass at `13d9883531b9` (log `.autonomous/logs/integration/osc-001/settings-ui.log`)

### OSC-002 OSC message parser (integrated)
- `python3 scripts/check_compliance.py`: pass at `e0b3e36021ba` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-002/20261113T114747/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `e0b3e36021ba` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-002/20261113T114747/docs.log`)
- `swift test --package-path Packages/PerformanceControl`: pass at `e0b3e36021ba` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-002/20261113T114747/swift-test_PerformanceControl.log`)
- `post-merge: PerformanceControl xcodebuild test on iPhone 17 sim (73, incl. 24,000-packet fuzz and loopback bundle); projectM-iOSTests 172 + OSCReceiverUITests 14.7 s`: pass at `3b3a60649025` (log `.autonomous/logs/integration/mod-014-osc-002/perf-sim.log`)

### OSC-007 OSC network access switch (integrated)
- `python3 scripts/check_compliance.py`: pass at `30fe777ae19d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-007/20261113T120523/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `30fe777ae19d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/OSC-007/20261113T120523/docs.log`)
- `post-merge: projectM-iOSTests 184 incl. OSCNetworkAccessTests (real listener ready/cancelled), OSCNetworkAccessUITests 14.9 s, OSCReceiverUITests 14.8 s, CameraPrivacyStatusUITests 14.8 s (shared status stack) on iPhone 17 iOS 27.2 sim`: pass at `ade4dfec39a5` (log `.autonomous/logs/integration/osc-007-shd-001/app-tests.log`)

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

### SHD-001 Procedural material catalog (integrated)
- `python3 scripts/check_compliance.py`: pass at `67186e7fa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHD-001/20261113T120524/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `67186e7fa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHD-001/20261113T120524/docs.log`)
- `xcodebuild -scheme ANGLERendering -destination id=45ECED7B-7ADD-40B8-BC3C-5E3CD0714B85 CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `67186e7fa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHD-001/20261113T120524/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/Compositor`: pass at `67186e7fa06d` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHD-001/20261113T120524/swift-test_Compositor.log`)
- `post-merge: Compositor xcodebuild test on iPhone 17 sim (92: ProceduralMaterialsTests 31, CompositorTests 61); app builds and 184 app unit tests pass with the extended Compositor product`: pass at `ade4dfec39a5` (log `.autonomous/logs/integration/osc-007-shd-001/compositor-sim.log`)

### SHOW-011 Tap tempo (integrated)
- `python3 scripts/check_compliance.py`: pass at `725551081f5c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHOW-011/20261113T104510/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `725551081f5c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHOW-011/20261113T104510/docs.log`)
- `swift test --package-path Packages/PerformanceControl`: pass at `725551081f5c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHOW-011/20261113T104510/swift-test_PerformanceControl.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `725551081f5c` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/SHOW-011/20261113T104510/swift-test_VisualGenerators.log`)
- `post-merge: xcodebuild test projectM-iOSTests (146) + TapTempo/RouteIndicator/NativeVisual UI tests (6) on iPhone 17 iOS 27.2 sim`: pass at `11329d52e6dc` (log `.autonomous/logs/integration/show-011/app-tests.log`)
- `post-merge: PerformanceControl xcodebuild test on iPhone 17 sim (25)`: pass at `11329d52e6dc` (log `.autonomous/logs/integration/show-011/perf-sim.log`)

### VIS-001 Circular spectrum (integrated)
- `python3 scripts/check_compliance.py`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/autonomous-tests.log`)
- `xcodebuild -scheme ANGLERendering -destination id=77E17861-E687-4274-8A84-14224F32BE3E CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/sim-test_ANGLERendering.log`)
- `swift test --package-path Packages/AnalysisFeatures`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/swift-test_AnalysisFeatures.log`)
- `swift test --package-path Packages/AudioCore`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/swift-test_AudioCore.log`)
- `swift test --package-path Packages/CaptureKit`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/swift-test_CaptureKit.log`)
- `swift test --package-path Packages/CaptureUI`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/swift-test_CaptureUI.log`)
- `swift test --package-path Packages/Diagnostics`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/swift-test_Diagnostics.log`)
- `xcodebuild -scheme Rendering-Package -destination id=77E17861-E687-4274-8A84-14224F32BE3E CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 test`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/sim-test_Rendering.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `7fa6d4e0f3c1` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-001/20261113T080701/swift-test_VisualGenerators.log`)
- `integration checkout, full preset library: VisualGenerators 40 on iOS 27.2 sim (render tests ran) and 37 with -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE; xcodebuild projectM-iOS test: projectM-iOSTests 131 pass; UI 21 pass (NativeVisual, Visualizer, Settings, Status); 0 PosterBoard reports`: pass at `48285d4` (log `.autonomous/logs/integration/vis-001/app-tests.log`)

### VIS-002 Linear spectrum (integrated)
- `python3 scripts/check_compliance.py`: pass at `f3a531c11e88` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-002/20261113T102444/compliance.log`)
- `python3 scripts/validate_docs.py`: pass at `f3a531c11e88` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-002/20261113T102444/docs.log`)
- `python3 scripts/test_scripts.py`: pass at `f3a531c11e88` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-002/20261113T102444/script-tests.log`)
- `python3 scripts/autonomous/tests/test_autonomous.py`: pass at `f3a531c11e88` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-002/20261113T102444/autonomous-tests.log`)
- `swift test --package-path Packages/VisualGenerators`: pass at `f3a531c11e88` (log `/Users/coast/Documents/GIT/projectm-ios/.autonomous/logs/VIS-002/20261113T102444/swift-test_VisualGenerators.log`)
- `integration checkout: VisualGenerators 95 on iOS 27.2 sim; app: projectM-iOSTests 135, UI 3 (LinearSpectrum, Glow x2), 100 s wall; 0 PosterBoard reports`: pass at `c2b2f75` (log `.autonomous/logs/integration/vis-002/app-tests.log`)
