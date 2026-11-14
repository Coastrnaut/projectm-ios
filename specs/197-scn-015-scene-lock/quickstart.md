# Quickstart: SCN-015 Scene Lock Mode

1. `xcodegen generate`; create simulator "SCN15 iPhone 17" (iOS 27.2).
2. `xcodebuild build-for-testing -scheme projectM-iOS ...`, then
   `test-without-building -only-testing:projectM-iOSTests/SceneLockAcceptanceTests` — every edit refused with byte-identical scene, show and settings; cues apply; unlock restores edits; persistence.
3. `-only-testing:projectM-iOSUITests/SceneLockUITests` — lock, swipe-delete does nothing, Next advances, unlock (< 30 s).
