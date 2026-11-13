# Quickstart: SHOW-001 Manual Cue List

## Package (Mac host and Linux shape)

```bash
swift test --package-path Packages/ShowControl
swift test --package-path Packages/ShowControl -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
```

Expected: every test passes; the suite runs in well under 1 minute; `ShowAcceptanceTests` proves
SHOW-001-S1 (five cues, scripted steps, two identical runs), `ShowStoreTests` S2, `ShowPropertyTests` S3.

## App (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=SHOW1 iPhone 17' \
  -derivedDataPath .autonomous/derived-data-show-001 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests/ShowCoordinatorTests -only-testing:projectM-iOSUITests/ShowCueUITests
```

Expected: `ShowCoordinatorTests` (apply, blackout stays black, missing scene notice, add/edit/persist)
and `ShowCueUITests` (DEBUG seed `-uitestShowSeed`: five cues on cue 1; Next ×4 → cues 2…5 with the
`showActiveScene` probe; Previous → cue 4; `sourceStarts` = 1) pass; the UI test runs in under 30 s.

## Manual

Settings → Show → Add Current Scene with two different visuals; close Settings; the controls show
"Cue … of 2"; Next/Previous and the arrow keys (hardware keyboard) switch the look; black out (B) and
press Next: the output stays black; Restore shows the new cue.
