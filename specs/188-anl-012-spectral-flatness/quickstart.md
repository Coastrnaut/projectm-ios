# Quickstart: ANL-012 Spectral Flatness

From the worktree:

```bash
swift test --package-path Packages/AnalysisFeatures --filter SpectralFlatnessTests
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE --filter SpectralFlatnessTests
swift test --package-path Packages/ParameterGraph --filter 'AudioFeatureSourceTests|AudioFeatureModulatorTests|ExpressionEvaluationTests|ExpressionPathologicalTests'
swift build --package-path Packages/VisualGenerators
```

Expected (contract C1-C3): a sine reads < 0.05, every seeded white-noise frame > 0.4 with a mean in
0.45…0.65, the sine at least 0.3 below the noise; a flat spectrum reads 1 within 10⁻⁹; silence,
dither and NaN input read 0 and finite; backends agree within 10⁻⁶; the pipeline's noise frames
read above its tone frames.

App (simulator "ANL12 iPhone 17", iOS 27.2): `xcodegen generate`, `build-for-testing`, then
`test-without-building -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests/testFlatnessBindsAndDrivesTheGlow`.
Expected (C4): the glow intensity follows the flatness value and the inspector name reads "Flatness".
