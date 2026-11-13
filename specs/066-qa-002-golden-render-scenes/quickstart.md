# Quickstart: QA-002 Golden Render Scenes

## Run the suite

```bash
swift test --package-path Packages/RenderGoldens                    # macOS host goldens
swift test --package-path Packages/RenderGoldens -Xswiftc -DCOMPOSITOR_NO_METAL \
  -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE      # Linux shape (no GPU part)
cd Packages/RenderGoldens && xcodebuild test -scheme RenderGoldens -destination id=<sim udid> \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

Expected: every test passes; the suite prints one line per compared capture.

## Review a failure

Open `Packages/RenderGoldens/.build/golden-diffs/<class>/summary.txt`, then the folder of each failed
capture (`expected.png`, `actual.png`, `diff.png`). In Xcode the same images are attachments of the
failed test in the `.xcresult`.

## Re-record on purpose

```bash
GOLDEN_RECORD=1 swift test --package-path Packages/RenderGoldens --filter GoldenRenderSuiteTests
cd Packages/RenderGoldens && TEST_RUNNER_GOLDEN_RECORD=1 xcodebuild test -scheme RenderGoldens \
  -destination id=<iOS 27.2 sim udid> -only-testing:RenderGoldensTests/GoldenRenderSuiteTests ...
git diff --stat Packages/RenderGoldens/Goldens   # review the changed PNGs before committing
```

With `CI` or `GITHUB_ACTIONS` set, recording fails and writes nothing.

## Scenario checks

1. Deliberate regression: `GoldenRegressionProofTests` passes (a changed parameter fails comparison
   and writes the artifacts).
2. Integrity: `GoldenIntegrityTests` passes on the committed set and fails on doctored copies.
3. Determinism: `GoldenDeterminismTests` renders every scene twice with equal hashes.
