# Quickstart: validating CMP-008 Gradient Masks

Run from the worktree root on the Mac Studio. Simulator results are not device evidence.

1. CPU reference and GPU read-back (CMP-008-S1, S2):
   `swift test --package-path Packages/Compositor --filter 'LayerGradient'` — expect all pass; the
   GPU test prints per-segment sample counts and the largest monotonic and reference errors.
2. Linux shape: `swift build --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL
   -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE` and the same flags with
   `--filter LayerGradientReferenceTests`.
3. Scene round trips (CMP-008-S4): `swift test --package-path Packages/SceneFormat` (includes the QA-004
   meta-test and `SceneGradientMaskTests`).
4. Goldens (CMP-008-S3): `swift test --package-path Packages/RenderGoldens --filter GradientMask` on the
   host; the same suite on the "CMP8 iPhone 17" iOS 27.2 simulator with `xcodebuild test -scheme
   RenderGoldens -only-testing:RenderGoldensTests/GradientMaskGoldenTests`. Record once with
   `GOLDEN_RECORD=1` (refused under CI).
5. GPU bench (CMP-008-S5): `CMP008_BENCH=1 swift test --package-path Packages/Compositor
   --filter testGradientGPUTimeBench` (Debug: the Compositor tests do not build with `-c release`, their
   DEBUG-only fault-injection hooks are compiled out; the GPU time is the run-time-compiled shader's either way);
   record in `docs/test-reports/gradient-masks.md` as not device evidence.
6. App: unit `LayerGradientEditTests`; UI test
   `LayerInspectorUITests/testGradientStopsCanBeAddedEditedAndUndone` on the "CMP8 iPhone 17"
   simulator (< 30 s).
7. Device `{device}`: D1, the GPU time of a full-screen gradient layer (Release, automation build).
