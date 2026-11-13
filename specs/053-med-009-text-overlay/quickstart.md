# Quickstart: MED-009 Text Overlay

Budgets (owner rule 7): unit tests about 1-2 s each, package suite under 1 minute, the UI test under
30 s. Simulator results are never device evidence (Constitution X).

## A. Package (host macOS and Linux shape)

```bash
swift test --package-path Packages/Compositor --filter TextLayerTests
swift test --package-path Packages/Compositor --scratch-path .build/linuxshape \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter TextLayerTests
```

Expected: spec, cleaning, limits, direction, codable and layout tests pass in both; rasterizer and
layer tests run on the host only (CoreText, Metal) and pass: determinism (identical bytes), Unicode
fixtures non-empty on the expected side, 64 × 64 readback within 1/255.

## B. Package on the iOS simulator

`xcodebuild test -scheme Compositor -destination 'platform=iOS Simulator,id=<udid>'` — every
Compositor test passes, TextLayerTests included.

## C. App (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath .autonomous/derived-data-med-009 CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/TextOverlayUITests
```

Expected: `TextOverlayStoreTests` pass; `TextOverlayUITests` seeds "Hello 👋🏽 مرحبا", chooses Text,
reads the visual's value (the message) and `textRendering` (size and checksum), relaunches without
the seed and reads equal values (MED-009-S1).

## D. Device `{device}` (owner, D1 and D3)

1. Settings › Visual › Text. Type an Arabic message with the Arabic keyboard: it runs right to left;
   Leading puts it at the right edge, Trailing at the left.
2. Type emoji with skin tones and a family emoji: each shows as one picture; the 280 limit counts
   each as one.
3. Settings › Accessibility › Display & Text Size › Larger Text at the largest size: the Text editor
   rows stay usable (labels wrap, controls reachable).
4. Relaunch: the same text, unchanged.
