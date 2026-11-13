# Quickstart: MED-014 Safe Media Decoder

Prerequisites: the Mac Studio toolchain (`python3 scripts/verify_environment.py`), the worktree's
`xcodegen generate`, a simulator of your own on iOS 27.2.

1. Package on the host: `swift test --package-path Packages/Compositor --filter 'MediaSniffingTests|SafeDecoderTests'`
   — the fixture table (F1-F16) gives its exact outcomes, the fuzz ends with typed results, the
   isolation test keeps producing frames.
2. Linux shape: `swift test --package-path Packages/Compositor --scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MediaSniffingTests`.
3. Simulator package run: `xcodebuild test -scheme Compositor -destination 'platform=iOS Simulator,id=<udid>'`.
4. App: `xcodebuild test -scheme projectM-iOS … -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/SafeMediaUITests -only-testing:projectM-iOSUITests/PhotoLayerUITests -only-testing:projectM-iOSUITests/VideoLayerUITests`;
   grep the log for "priority inversion" (expected: none from the import path).
5. Device (`{device}`, owner): import a real HEIC, a ProRAW DNG, a panorama and an HDR video on D1
   and D3; each imports and renders as before (no false refusal).
