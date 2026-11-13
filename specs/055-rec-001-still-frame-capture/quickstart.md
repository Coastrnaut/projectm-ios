# Quickstart: REC-001 Still Frame Capture

Owner rule 7 budgets apply; never the Simulator panel tool (owner rule 8).

```bash
# Package (host: conversion, fixture encoding, metadata, compositor GPU capture)
swift test --package-path Packages/Compositor --filter 'FrameCapture|CompositorCapture'
# Linux shape (conversion and gate only)
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter FrameCapture
# projectM capture (simulator)
xcodebuild test -scheme ANGLERendering -destination "id=$SIM" -only-testing:ANGLERenderingTests/ANGLECaptureTests
# App unit + UI
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=$SIM" \
  -only-testing:projectM-iOSTests/FrameCaptureAppTests -only-testing:projectM-iOSUITests/FrameCaptureUITests
```

Expected: fixture PNG 64×48 with alpha, HEIF 64×48 without; compositor capture at the target size;
UI probe `png <w>x<h> opaque` for the Circular Spectrum.

## Device stage (owner, last)

1. D1 (iOS 27) and D3 (iPadOS 26.5): Save Frame → PNG → Files → On My iPhone/iPad; open it in Files.
2. Same with HEIF, saved to iCloud Drive; open it; D3 confirms HEIF on iOS 26.5.
3. With an external display connected (OUT-001), save a frame; the file has the display's pixel
   size and the projector showed nothing of the capture.
4. Black out the output, tap Save Frame: the notice appears and no sheet opens.
