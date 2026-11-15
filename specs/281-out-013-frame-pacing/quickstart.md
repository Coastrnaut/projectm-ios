# Quickstart: OUT-013 Frame Pacing per Output

1. Model (host, Linux-safe): `swift test --package-path Packages/Compositor --filter OutputFramePacingTests`
   — S1-S3: no device tick late by more than 1 ms over 10 simulated seconds, in flight ≤ 2, constant max depth, every
   drop counted; the blocking control is late by ≥ 50 ms.
2. App and ANGLE (simulator "OUT13 iPhone 17", iOS 27.2): `xcodebuild build-for-testing` then `test-without-building
   -only-testing:projectM-iOSTests/OutputFramePacingAppTests` and the ANGLERendering scheme's `ANGLEOutputPacingTests`.
3. `{device}` (OUT-013-T12): D1 with a real HDMI display (USB-C adapter) and a deliberately heavy preset at the external
   display's native resolution: the device's controls and HUD stay smooth while PERF-007's external "skipped" count and
   the visual's `outputPacing` drops rise.
