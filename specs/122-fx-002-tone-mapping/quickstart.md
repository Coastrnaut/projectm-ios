# Quickstart: FX-002 Tone Mapping

Prerequisites: the Mac Studio toolchain (`python3 scripts/verify_environment.py`), the worktree on
`feature/fx-002`.

1. Reference (Linux shape):
   `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter ToneMapReferenceTests`
   Expect: hand-checked values, identity in range, ray monotonicity, 10,000-colour properties pass.
2. GPU (Mac host): `swift test --package-path Packages/Compositor --filter ToneMapOutputTests`
   Expect: the gradient is monotonic, in 0…1 and NaN-free on the screen and capture formats and matches the
   reference; recording and capture equal the screen; 1↔16 keeps the limiter's gain at 1, 0↔16 lowers it;
   the counter counts NaN/Inf pixels once; the GPU timing line is printed.
3. Regressions: `swift test --package-path Packages/Compositor`, then `Packages/RenderGoldens` (no golden
   changes), `Packages/VisualGenerators`, `Packages/SceneFormat`, `Packages/ImportFuzz`.
4. App unit tests on an own simulator ("FX2 iPhone 17", iOS 27.2) with `-only-testing:projectM-iOSTests`.
5. Device (`{device}`, last stage): on D1, a scene with a glowing spectrum layer over a bright photo shows
   bright regions fading to white without hue shifts or broken pixels; frame rate as before.
