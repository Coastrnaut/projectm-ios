# Quickstart: UIX-008

1. `xcodegen generate`; build for testing on the "UIX8 iPad Pro" iOS 27.2 simulator.
2. App tests: `-only-testing:projectM-iOSTests/SceneDocumentEditorTests -only-testing:projectM-iOSTests/SceneEditorWindowRouterTests`.
3. UI test: `-only-testing:projectM-iOSUITests/SceneEditorWindowUITests` (under 30 s).
4. Regression: the OUT-001 external display UI tests and `SceneFoldersUITests`.
5. `{device}` D2 and D3 with Stage Manager: open two scenes in two windows beside the main window, edit and save
   each, confirm the live output never changes and both files changed.
