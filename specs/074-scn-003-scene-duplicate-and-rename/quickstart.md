# Quickstart: SCN-003 validation

Run from the worktree root on the Mac.

## A. Packages (host and Linux shape)

```bash
swift test --package-path Packages/SceneFormat --filter SceneEditingTests
swift test --package-path Packages/ShowControl
swift test --package-path Packages/SceneFormat --filter SceneEditingTests -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/ShowControl -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
```

Expected: all pass; the acceptance (SCN-003-S1), rename (S2), property (S3, ≤ 1 s) and name table (S4)
tests among them; each test under 10 s.

## B. App (own simulator)

```bash
xcrun simctl create "SCN3 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "platform=iOS Simulator,id=<udid>" \
  -derivedDataPath .autonomous/derived-data-scn-003 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/SceneDuplicateUITests \
  -only-testing:projectM-iOSUITests/ShowCueUITests > log.txt 2>&1
```

Expected: SCN-003-S5 — with `-uitestShowSeed`, Settings → Show → cue 2 → Duplicate Scene adds cue 3
"Build copy"; Rename Scene… "Build B" shows "Scene: Build B"; Next from cue 1 applies cue 2 (seed
scene 2) then cue 3 (a different scene ID, same visual). UI test under 30 s. Simulator results are
never device evidence.
