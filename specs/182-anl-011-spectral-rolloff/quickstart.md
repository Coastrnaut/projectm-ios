# Quickstart: ANL-011 Spectral Rolloff

From the worktree:

```bash
swift test --package-path Packages/AnalysisFeatures --filter SpectralRolloffTests
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE --filter SpectralRolloffTests
swift test --package-path Packages/ParameterGraph --filter 'AudioFeatureSourceTests|AudioFeatureModulatorTests|ExpressionEvaluationTests|ExpressionPathologicalTests'
swift build --package-path Packages/VisualGenerators
```

Expected: the reference spectra (single tone, two tones 9:1 and 4:1, flat to a cutoff, linear power
ramp) read their analytic rolloff within half a bin at p = 0.85, 0.5 and 0.99; silence, dither and
NaN input read 0 and finite; backends agree within 0.001 bin; the pipeline's noise frames read above
its low-tone frames.

App (simulator "ANL11 iPhone 17", iOS 27.2): `xcodegen generate`, `build-for-testing`, then
`test-without-building -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests/testRolloffBindsAndDrivesTheGlow`.
Expected: the glow intensity follows the rolloff value and the inspector name reads "Rolloff".
