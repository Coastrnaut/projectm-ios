# Quickstart: MED-004 Video Playback Speed

All commands from the repository (worktree) root. Budgets: unit test about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s (owner rule 7). Simulator results are never device
evidence.

## A — Package (Mac host)

```bash
swift test --package-path Packages/Compositor --filter 'VideoSpeedTests|VideoLoopTests|VideoPipelineTests|VideoLayerTests'
swift test --package-path Packages/SceneFormat --filter SceneVideoLoopTests
swift test --package-path Packages/LibraryBackup
```

Expected: the acceptance (0.5×: 1 s of video per 2 s presented, within one picture interval; 1×
and 2× likewise), continuity at a change, loop wraps at 0.5× and 2× with gap 0 at the fake reader,
the real H.264 fixture showing the expected indices.

## B — Linux shape (Mac)

```bash
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'VideoSpeedTests|VideoLoopTests'
```

## C — App unit and UI tests (own simulator)

```bash
xcrun simctl create "MED4 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath .autonomous/derived-data-med-004 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/VideoSpeedUITests \
  -only-testing:projectM-iOSUITests/VideoLayerUITests -only-testing:projectM-iOSUITests/VideoLoopUITests
```

Expected: `VideoSpeedUITests` sets 0.5× in Settings → Video and reads `videoSpeed` = `50 ratio≈0.500`
(± 0.05) while `videoFrameIndex` keeps advancing.

## D — Checks

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && python3 scripts/check_motion_policy.py
python3 scripts/check_permission_catalog.py && python3 scripts/check_status_events.py && python3 scripts/test_scripts.py
python3 scripts/check_privacy_manifest.py <built Debug .app>
```

## E — Device stage `{device}` (D1)

Pick a clip with the system picker, set 2×: it keeps up or drops late pictures without slowing;
0.25× looks smooth; the music from In-App Playback is unchanged at every speed.
