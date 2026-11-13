# Quickstart: SHD-009 Expression Mapping DSL

Validation on the Mac (no GPU, simulator or device needed).

1. Package tests on the host (expect every `ParameterExpressionTests` test to pass, suite < 1 min):

   ```bash
   swift test --package-path Packages/ParameterGraph
   ```

2. Linux build shape (the dependant package compiles and passes with Linux conditionals):

   ```bash
   swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL \
     -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape
   ```

3. Repository checks:

   ```bash
   python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
   ```

Expected outcomes: the valid table evaluates exactly (S1), the rejection table matches every
message and position of the contract's E7 (S2), numeric cases are finite (S3), the seeded fuzz
completes (S4), compiled bytes are identical (S5), the source scan is clean (S6).

Usage (contract E8):

```swift
let compiled = try CompiledExpression(source: "let k = audio.onset * 2; clamp(k - 0.5, 0, 1)")
let mapping = ExpressionMapping(expression: compiled, outputStart: 0.2, outputEnd: 0.9)
let value = mapping.map(ExpressionInputs(frame: frame, timeSeconds: t))
```
