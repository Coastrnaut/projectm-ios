# OUT-001 External display scene: test report

Spec: `specs/049-out-001-external-display-scene`. ADR-0023. The build machine of record (Mac Studio,
Xcode 27.2) ran everything here on 2026-11-13, in the `feature/out-001` worktree.

**Simulator results are never device evidence (Constitution X).** The physical displays are
covered by OUT-001-T15 to T18 `{device}`; they are still open and need the owner.

## Simulator hot-plug (OUT-001-T14, quickstart B)

The simulator's TVOut screen (`external-0`, 720 × 480 at scale 1) is connected and disconnected
headless. The Simulator app's menu and the Simulator panel tool are not used (owner rule 8).

```bash
xcrun simctl launch <udid> org.projectmios.ProjectMiOS -uitestDiagnostics -autostart inAppPlayback -uitestUnlocked NO
xcrun simctl io <udid> screenConfig --display external power on
xcrun simctl io <udid> screenshot --display external ext.png
xcrun simctl io <udid> screenshot --display internal dev.png
xcrun simctl io <udid> screenConfig --display external power off
xcrun simctl spawn <udid> log show --last 1m --info --predicate 'category == "ExternalDisplay"'
```

| Runtime | Path | Connect | External screen | Device | Disconnect |
|---|---|---|---|---|---|
| iOS 27.2 (iPhone 17) | SwiftUI scene accessory | slot connected 720 × 480 @1, target external | projectM alone, filling 720 × 480 | black with "Showing on external display" and the source indicator | target device; projectM full screen on the device again; app still running |
| iOS 26.5 (23F77, iPhone 17) | Info.plist role → `ExternalDisplaySceneDelegate` | "external display scene connecting (role UIWindowSceneSessionRoleExternalDisplayNonInteractive)", then 720 × 480 @1, foreground | projectM alone | (not captured) | target device; projectM on the device again |

Findings:

- On iOS 27.2 the plist role alone gave the app no scene: SpringBoard mirrored the device. The iOS
  27 scene accessory is therefore required there (research OUT-001-D1).
- When the accessory connects, the iOS 27.2 simulator connects it, disconnects it about 20 ms later
  and connects it again. The coordinator follows each step: target external, device, then external
  again. Nothing restarts, and the final state is correct.
- Screenshots are not committed: simulator exports are kept out of git.

## Automated tests

| Command | Result | Time |
|---|---|---|
| `swift test --package-path Packages/PresentationLifecycle` | 32 tests, 0 failures (ExternalDisplayRoutingTests: 10) | 1.4 s wall |
| `swift test --package-path Packages/Compositor --filter ExternalOutputSizeTests` | 3 tests, 0 failures; strobe across the move: worst 1 transition per window with Reduce flashing (limit 4), 6 with the always-on cap (limit 6); gain after the move 0.004 / 0.095; GPU and CPU gains differ by ≤ 5e-10 | 1.7 s |
| ANGLERendering on iOS 27.2: `-only-testing:ANGLERenderingTests/FlashLimiterTests` | 7 tests, 0 failures (new `testStrobeHistorySurvivesAnExternalResize`: 0.05 s) | 7.6 s |
| projectM-iOS on iOS 27.2: `-only-testing:projectM-iOSTests` | 202 tests, 1 failure: the known worktree failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (preset submodules not checked out in worktrees). ExternalDisplayCoordinatorTests: 9 passed in 0.2 s | 5.3 s |
| projectM-iOS UI tests on iOS 27.2: ExternalDisplayUITests, NativeVisualUITests, CameraUITests | 7 tests, 0 failures. ExternalDisplay 10.3 s; NativeVisual 9.9-18.8 s; Camera 10.1 s and 12.4 s | 95.6 s |
| PhotoLayerUITests (the Photo host's scene filter changed) | 1 test, 0 failures | 22.7 s |

PosterBoard crash reports: 32 before and 32 after (owner rule 5).

## Not verified here

- Physical displays: USB-C/HDMI, AirPlay to an Apple TV, Stage Manager on D2, hot-plug during
  playback, and resolution and refresh changes (OUT-001-T15 to T18).
- The iOS 26.5 SDK build. CI's Xcode 26 job compiles the accessory out (`#if compiler(>=6.4)`). Only
  the iOS 27.2 SDK was available here.
- The frame-rate cost at the external display's resolution, and pacing against 50 Hz and 24 Hz
  displays (OUT-001-T18, OUT-013).
