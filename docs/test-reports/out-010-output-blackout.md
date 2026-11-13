# OUT-010 Output blackout isolation: test report

Spec: `specs/051-out-010-output-blackout-isolation`. ADR-0023 decision 8. The build machine of
record (Mac Studio, Xcode 27.2) ran everything here on 2026-11-13, in the `feature/out-010`
worktree, on a dedicated iPhone 17 simulator (iOS 27.2), deleted afterwards.

**Simulator results are never device evidence (Constitution X).** Physical displays are
OUT-010-T15 `{device}`, still open for the owner.

## "Within one frame"

Frames are counted, not timed:

- Model (`OutputBlackoutTests`, fake 60 Hz frame clock): from every phase, the first frame after a
  Black out tap is black, and every frame after it until Restore.
- App (`OutputBlackoutCoordinatorTests`, real slot views): before `setBlackout(true)` returns, the
  slot holding the visual has an opaque cover that fills it and has no animation, on the device and
  on the external slot. It is part of the current Core Animation transaction, so the next composited
  frame is black.

## Simulator real external screen (OUT-010-T14, quickstart C)

```bash
xcrun simctl launch --terminate-running-process <udid> org.projectmios.ProjectMiOS -uitestDiagnostics -autostart inAppPlayback -uitestUnlocked NO -uitestStartBlackedOut
xcrun simctl io <udid> screenConfig --display external power on
xcrun simctl io <udid> screenshot --display external ext-black.png
xcrun simctl launch --terminate-running-process <udid> org.projectmios.ProjectMiOS -uitestDiagnostics -autostart inAppPlayback -uitestUnlocked NO
xcrun simctl io <udid> screenshot --display external ext-live.png
xcrun simctl io <udid> screenConfig --display external power off
```

| State | External screen (720 × 480) | Device |
|---|---|---|
| Blacked out | every pixel 0 (largest channel value 0 over the whole image) | black, "Output blacked out" badge with Restore, "External display blacked out", source indicator "In-App Playback · Active audio" |
| Live | the visualization (largest channel value 255) | OUT-001's note |

The log showed the visual placed in the external slot (720 × 480) while blacked out: the visual is
kept in its slot and covered, as designed. Screenshots are not committed (simulator exports stay
out of git).

## Automated tests

| Command | Result | Time |
|---|---|---|
| `swift test --package-path Packages/PresentationLifecycle` | 41 tests, 0 failures (OutputBlackoutTests 9: one frame, fade 1 s / 4 s, white rise ≤ 0.25/s with Reduce flashing, restore spacing, toggling every frame, every 0.15 s and an adversary at 60 and 120 Hz: ≤ 4 transitions per window) | 0.01 s tests, 7 s wall with build |
| projectM-iOS on iOS 27.2: `-only-testing:projectM-iOSTests` | 209 tests, 1 failure: the known worktree failure `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (preset submodules not checked out). OutputBlackoutCoordinatorTests 7/7 in 0.02 s, including the blend check (a half-opaque cover over white composites to encoded 127.5 ± 4, not linear-light 186) | about 30 s |
| UI tests on iOS 27.2: OutputBlackoutUITests, ExternalDisplayUITests, NativeVisualUITests | 6 tests, 0 failures. OutputBlackout 17.1 s (23.6 s alone); ExternalDisplay 12.4 s; NativeVisual 8.9-18.3 s | 80 s |
| `check_compliance.py`, `validate_docs.py` | OK | |

PosterBoard crash reports: 32 before and 32 after (owner rule 5).

## Not verified here

- Physical displays: HDMI and AirPlay on D1 and D2, the time from the tap to black on a real
  display (240 fps camera optional), unplug while blacked out (OUT-010-T15).
- The iOS 26.5 SDK build (CI's Xcode 26 job builds it; only the iOS 27.2 SDK is installed here).
- The blend space on a device (the check ran on the simulator's renderer).
