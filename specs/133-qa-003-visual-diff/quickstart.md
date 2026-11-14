# Quickstart: QA-003 Visual Diff Tolerances

## Host (macOS)

```bash
swift test --package-path Packages/RenderGoldens --filter 'ImageDiff|GoldenComparison|GoldenRenderSuite|OscilloscopeGolden'
```

Expected: `ImageDiffAcceptanceTests` pass (noise passes, moved/scaled/removed shape fails), boundary
tests pass, every golden capture prints `PASS` or `identical`.

## Linux shape

```bash
swift test --package-path Packages/RenderGoldens -Xswiftc -DCOMPOSITOR_NO_METAL \
  -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
```

## Simulator (QA3, iOS 27.2)

```bash
cd Packages/RenderGoldens && xcodebuild test -scheme RenderGoldens -destination id=<QA3 udid> \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

## Using the comparator in a test

```swift
let report = ImageDiff.compare(expected: golden, actual: frame, tolerance: .golden)
XCTAssertTrue(report.passed, report.summary)
```

Contract: [contracts/image-diff.md](contracts/image-diff.md). Device check: FINAL stage (`{device}`).
