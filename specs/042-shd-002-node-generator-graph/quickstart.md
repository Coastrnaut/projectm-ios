# Quickstart: SHD-002 Node-Based Generator Graph

Validation scenarios (Mac, worktree root).

1. Host tests (CPU and GPU): `swift test --package-path Packages/Compositor --filter GeneratorGraphTests`
   → all pass; the full package suite stays under 1 minute.
2. Linux shape (CPU only; GPU tests compile out):
   `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter GeneratorGraphTests`.
3. Simulator: from `Packages/Compositor`,
   `xcodebuild test -scheme Compositor -destination id=<iOS 27.2 udid> CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180`.
4. Docs and rules: `python3 scripts/validate_docs.py`, `python3 scripts/check_compliance.py`.
5. Host GPU cost (research SHD-002-D2, on demand): `SHD002_BENCH=1 swift test --package-path Packages/Compositor --filter GraphCostBench`.

Expected outcomes: acceptance "compiles deterministically" = GraphCompilerTests determinism tests
and GraphRenderTests determinism; "rejects cycles" = GraphValidationTests cycle tests (readable
paths); flash = GraphFlashSafetyTests; safety = GraphSourceSafetyTests.

Device stage (last, `{device}`): frame cost of the 12-node bench graph on D1-D3 (SHD-002-T24).
