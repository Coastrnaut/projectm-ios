# Quickstart: CMP-014 checks

Run from the worktree root on the Mac.

1. Package tests (acceptance, model, cache, flash, timing):
   `swift test --package-path Packages/Compositor --filter SceneTransition`
   Expect every `SceneTransition*` test to pass; the timing test prints `CMP-014 GPU`.
2. Whole Compositor suite: `swift test --package-path Packages/Compositor` (under 1 minute).
3. Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
   and the model tests with the same flags (`--filter SceneTransitionModelTests`).
4. Regressions: `swift test --package-path Packages/<P>` for RenderGoldens (goldens unchanged),
   SceneFormat, ShowControl, ImportFuzz, SceneArchive.
5. App unit tests on a private simulator (`xcrun simctl create "CMP14 iPhone 17" "iPhone 17"
   com.apple.CoreSimulator.SimRuntime.iOS-27-2`), `-only-testing:projectM-iOSTests`, then delete it.
6. Scripts: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`.
