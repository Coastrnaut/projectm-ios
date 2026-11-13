# Quickstart: SHD-010 Expression Sandbox Budgets

Validation on the Mac (no GPU, simulator or device needed).

1. Package tests on the host (every `ParameterExpressionTests` test passes, suite < 1 min):

   ```bash
   swift test --package-path Packages/ParameterGraph
   ```

2. Linux build shape:

   ```bash
   swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL \
     -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape
   ```

3. Repository checks:

   ```bash
   python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
   ```

4. Informational host measurement (not a pass criterion; prints ns per cost unit):

   ```bash
   PARAMETER_EXPRESSION_BENCH=1 swift test --package-path Packages/ParameterGraph \
     -c release --filter ExpressionCompileWorkTests/testInformationalHostCost
   ```

Expected: fixtures give their contract B3 outcomes (S1), accounting refusals match B2 (S2), work
stays within B4 (S3, S4).

Usage (contract B1):

```swift
var frameSet = ExpressionFrameSet()                       // off the frame loop
let handle = try frameSet.admit(try CompiledExpression(source: formula))
let snapshot = frameSet.snapshot                          // hand to the render loop
let n = snapshot.evaluate(inputs, into: resultBuffer)     // per frame: no allocation, no clock
```
