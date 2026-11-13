# Quickstart: SCN-010 validation

1. Model (host and Linux shape):
   `swift test --package-path Packages/SceneFormat --filter SceneHistoryTests`
   `swift test --package-path Packages/SceneFormat --filter SceneHistoryTests -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
   Expect: the acceptance sequence, redo, coalescing, no-op, bounds and the fixed-seed property test
   pass, each in about a second or less.
2. App (own simulator, see the feature brief): `xcodegen generate`, then `xcodebuild test` with
   `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/SceneUndoUITests` and the
   SceneAutosave, NativeVisual and ShowCue UI suites. Expect: Settings → Circular Spectrum → 16 bars
   → glow intensity changed → Undo twice restores both → Redo moves forward; `sourceStarts` stays 1.
3. `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py` exit 0.
