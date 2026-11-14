# Quickstart: SHOW-002 Timed Cue Advance

## Package (host, < 1 min)

```bash
swift test --package-path Packages/ShowControl --filter 'ShowAdvanceTimelineTests|ShowDwellDocumentTests'
```

Expected: the five-cue acceptance (four advances at 10, 30, 60 and 100 s, none early, none twice), the jump,
manual-reset and hold cases, and the file round trip pass.

## App (simulator "SHOW2 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=SHOW2 iPhone 17' \
  -derivedDataPath .autonomous/derived-data-show-002 CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/ShowAutoAdvanceCoordinatorTests
xcodebuild test-without-building ... -only-testing:projectM-iOSUITests/ShowAutoAdvanceUITests
```

Expected: the coordinator advances once per due cue with a manual clock, holds on pause and blackout, refuses
a dwell edit while locked; the UI test sees cue 1 advance to cue 2 by itself (2 s dwell) and the countdown text.

## By hand

Settings → Show → a cue's context menu → Advance After… → 5 s. Back in the visualizer, press Next: the controls
show "Next in 0:05" and the show moves on by itself; Pause holds it.
