# Quickstart: CMP-003 Opacity per Layer

Validation on the build Mac (no device needed for this row; the device frame cost is CMP-002-T15).

1. Host tests (GPU at 64 × 64 and CPU):
   `swift test --package-path Packages/Compositor --filter 'LayerOpacity'` → the animator tests and
   the opacity composite tests pass; then the whole package: `swift test --package-path Packages/Compositor`.
2. Linux shape (CPU only):
   `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
   → `LayerOpacityAnimatorTests` run and pass.
3. Simulator: from `Packages/Compositor`,
   `xcodebuild test -scheme Compositor -destination id=<iOS 27.2 udid> CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180`.
4. Expected: opacity 0 output equals the output without the layer; opacity 1 is bit-identical to
   the CMP-002 output; 0.5 red over blue reads (0.5, 0, 0.5, 1) within 1/255; the 30 Hz opacity
   strobe is limited with Reduce flashing on (contract: [layer-opacity.md](contracts/layer-opacity.md)).
