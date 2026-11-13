# Quickstart: validating UIX-001 Guided First Scene

## Prerequisites

- Mac Studio, Xcode 27.2, `xcodegen generate` in the worktree, preset submodules initialised
  (`git submodule update --init --depth 1 Vendor/presets/*`), engine and ANGLE xcframeworks in
  `Build/`.
- A dedicated simulator: `xcrun simctl create "UIX1 iPhone 17" "iPhone 17"
  com.apple.CoreSimulator.SimRuntime.iOS-27-2` (delete it afterwards).

## A. Unit tests (about 1 s)

```bash
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-uix-001 \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/GuidedFirstSceneTests
```

Expected: flow, stored state, launch rule and apply tests pass.

## B. Acceptance UI tests (each under 30 s)

Same command with `-only-testing:projectM-iOSUITests/GuidedFirstSceneUITests`:

1. `testNewUserFinishesOfflineAndTheSceneIsKept`: fresh install → notice → five steps (Circular
   Spectrum, glow on) → Play; `sourceStarts` = 1, `visualRunning` = yes, the scene is committed
   (`sceneAutosave` pending=0, committed>0), `sessionRecovery` reports `osc=off`, no system alert;
   relaunch: no tutorial, the chooser's In-App Playback row shows the restored Circular Spectrum.
2. `testSkipChangesNothingAndNeverReturns`: Skip on step 2 → chooser, nothing started; relaunch →
   no tutorial.
3. `testEveryPrimaryButtonIsReachableAtTheLargestTextSize`: AX5 text size, every step's primary
   button revealed and hittable.
4. `testReopenFromSettingsKeepsTheRunningSource`: `-autostart inAppPlayback`, Settings › Guided first
   scene → Linear Spectrum → Play; the linear spectrum shows and `sourceStarts` stays 1.

## C. Regression (existing suites unaffected)

`-only-testing:` NativeVisualUITests, SessionRecoveryUITests, SettingsUITests and the app unit tests.

## D. Device ({device}, owner)

D1, fresh install, Airplane Mode on, VoiceOver on: go through the tutorial and Play; the scene plays
with no sign-in, network or permission prompt; every step reads heading, text, choices, buttons.
