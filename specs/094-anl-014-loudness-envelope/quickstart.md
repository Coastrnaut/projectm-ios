# Quickstart: ANL-014 Loudness Envelope

Run from the repository root (or the feature worktree).

1. Package tests on the host:
   `swift test --package-path Packages/AnalysisFeatures --filter LoudnessEnvelopeTests`
   Expect every test to pass; the step test prints the measured 90 % rise and fall times, which
   must equal the spec's documented lag within one frame.
2. Linux shape: `swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE`
   (whole suite; compare the duration with the baseline recorded in the spec).
3. ParameterGraph: `swift test --package-path Packages/ParameterGraph` (Loudness source and
   opcode 16).
4. Dependants: `swift build --build-tests` and `swift test` for VisualGenerators, PerformanceControl,
   Compositor, SceneFormat, RenderGoldens and ShowControl.
5. App: on a dedicated iOS 27.2 simulator, `xcodebuild test -scheme projectM-iOS
   -only-testing:projectM-iOSTests/AudioFeatureBindingAppTests CODE_SIGNING_ALLOWED=NO
   -test-timeouts-enabled YES -default-test-execution-time-allowance 180`, then the whole
   `projectM-iOSTests` bundle. Delete the simulator afterwards. Never use the Simulator panel tool.
6. Repository checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `test_scripts.py`.

Simulator results are not device evidence; the acceptance is the synthetic-PCM package tests.
