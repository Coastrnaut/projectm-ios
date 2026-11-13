# Quickstart: validating CMP-001

Prerequisites: the Mac Studio toolchain (`python3 scripts/verify_environment.py`), `Build/` with the
ANGLE and engine xcframeworks, the iOS 27.2 simulator. Contract: [contracts/layer-source.md](contracts/layer-source.md).

## A. Contract on the host (≈ 10 s)

```bash
swift test --package-path Packages/Compositor
swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL \
  -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE      # the Linux shape
```

Expected: every test passes; in the no-Metal shape the GPU tests are not compiled. The GPU tests on
the host prove CMP-001-S1 (half red over blue = (0.5, 0, 0.5, 1) within 1/255), S3 (fallbacks), S4
(two allocations over two sizes), S5 (a 60 Hz strobe yields at most 4/6 transitions per window per
area) and S6 (a spectrum layer's lit pixels lie in its bars).

## B. Simulator (iOS 27.2 iPhone Air)

```bash
cd Packages/Compositor && xcodebuild test -scheme Compositor -destination 'id=<udid>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO
cd Packages/ANGLERendering && xcodebuild test -scheme ANGLERendering -destination 'id=<udid>' \
  -only-testing:ANGLERenderingTests/ClientBufferSpikeTests -only-testing:ANGLERenderingTests/ProjectMLayerTests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO
```

Expected: the spike prints the extension string and passes (research CMP-001-D5); the projectM layer
composites a non-empty opaque frame and an upright test pattern.

## C. The app is unchanged

`xcodegen generate`, build `projectM-iOS` for the simulator, run the app unit tests and
`NativeVisualUITests`: all pass as before (CMP-001-R14).

## D. Devices ({device}, CMP-001-T20)

On D1-D3: the spike tests and a compositor frame-time sample with two spectrum layers and a
projectM layer. Not run in this row.
