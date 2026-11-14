# Quickstart: CMP-015 Layer Inspector

Prerequisites: `xcodegen generate`; preset submodules initialised; a private simulator
(`xcrun simctl create "CMP15 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2`).

1. Unit tests (model, help table, history, solo/mute, autosave round trip, pixel undo):
   `xcodebuild test -scheme projectM-iOS -destination id=<udid> -only-testing:projectM-iOSTests/LayerInspectorTests
   -only-testing:projectM-iOSTests/LayerInspectorRenderTests CODE_SIGNING_ALLOWED=NO
   -test-timeouts-enabled YES -default-test-execution-time-allowance 180`.
   Expected: all pass, each test a few seconds at most.
2. UI test: `-only-testing:projectM-iOSUITests/LayerInspectorUITests`. Expected: three rows; each
   selection shows the seeded values (contract L5); an opacity drag on the spectrum is one undo step and
   Undo restores 60 %.
3. Regression: `SceneUndoUITests`, `PhotoLayerUITests` and the whole `projectM-iOSTests`.
4. Type-check: build with `OTHER_SWIFT_FLAGS="-Xfrontend -warn-long-function-bodies=300 -Xfrontend
   -warn-long-expression-type-checking=150"`; no warning names a new file.
5. Scripts: compliance, docs, motion policy, permission catalog, status events, script tests.
