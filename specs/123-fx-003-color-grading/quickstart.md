# Quickstart: FX-003 Color Grading

1. Reference (Linux shape): `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL
   -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter ColorGradeReferenceTests`.
2. GPU: `swift test --package-path Packages/Compositor --filter 'ColorGrade|ToneMap|CompositeFlashGuard'` —
   neutral equals bypass (bit-identical in range), operators match the reference, the guard engages on a
   graded flash; the timing test prints neutral vs active medians.
3. Regressions: RenderGoldens, VisualGenerators, SceneFormat, ImportFuzz, LibraryBackup package tests.
4. App: on an own simulator, `-only-testing:projectM-iOSTests` and `-only-testing:projectM-iOSUITests/ColorGradeUITests`.
5. Device (`{device}`): on D1, Photo visual, set warm temperature, gain 1.5, saturation 0 → grey, reset →
   identical to before; frame rate unchanged in the performance overlay.
