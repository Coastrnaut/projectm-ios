# Quickstart: CMP-004 checks

All commands from the repository root (or the feature worktree).

1. CPU reference and GPU equations (Mac host, Metal):
   `swift test --package-path Packages/Compositor --filter 'LayerBlend|ContractTests'`
   Expect every test to pass; the GPU tests print the worst error per mode.
2. Whole Compositor suite (normal stacks unchanged): `swift test --package-path Packages/Compositor`.
3. Linux shape of the CPU reference:
   `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter LayerBlendReference`
4. Scene format: `swift test --package-path Packages/SceneFormat` (known names give no warning, unknown
   names survive load → capture).
5. Dependants: `swift test --package-path Packages/RenderGoldens` (goldens unchanged) and
   `swift test --package-path Packages/ImportFuzz`.
6. iOS simulator: `xcodebuild test -scheme Compositor -destination 'platform=iOS Simulator,id=<udid>'
   -only-testing:CompositorTests/LayerBlendCompositeTests -test-timeouts-enabled YES
   -default-test-execution-time-allowance 180`.
7. GPU time (Mac, Release, not device evidence):
   `CMP004_BENCH=1 swift test -c release --package-path Packages/Compositor --filter LayerBlendCompositeTests/testBenchGPUTimePerMode`
   Record the medians in `docs/test-reports/blend-modes.md`.
8. Repo checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
   `check_permission_catalog.py`, `test_scripts.py`.
