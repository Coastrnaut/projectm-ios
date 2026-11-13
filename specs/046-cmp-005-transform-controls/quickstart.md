# Quickstart: validating CMP-005 Transform Controls

Prerequisites: the worktree's packages build (`swift build --package-path Packages/Compositor`).

1. Host (matrix, round trip, GPU 64 × 64):
   `swift test --package-path Packages/Compositor --filter 'LayerTransform'` — expect
   `LayerTransformTests` (acceptance `testSavingAndReloadingReproducesTheTestMatrix`) and
   `LayerTransformCompositeTests` to pass; then the whole package suite (< 1 minute).
2. Linux shape (CPU part):
   `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
   — `LayerTransformTests` pass; the GPU tests compile out.
3. Simulator: from `Packages/Compositor`, `xcodebuild test -scheme Compositor -destination id=<udid>
   CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180`
   on a fresh iOS 27.2 simulator (delete it afterwards; count PosterBoard reports before and after).
4. Docs: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`.

Expected: the saved test transform reloads to a bit-identical matrix (see
[contracts/layer-transform.md](contracts/layer-transform.md)); the moved red square and the rotated
pattern land as described in the spec's User Story 2; identity output is bit-identical.
