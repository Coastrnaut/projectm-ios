# Tasks: REC-001 Still Frame Capture

**Input**: design documents in `specs/055-rec-001-still-frame-capture/` (spec, plan, research,
data-model, contracts/frame-capture.md, quickstart).

**Tests**: requested by the spec (REC-001-S1 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] REC-001-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Setup

- [ ] REC-001-T01 Add target `FrameCapture` (no dependencies) and test target `FrameCaptureTests` to `Packages/Compositor/Package.swift`; list it in the `Compositor` library product; `Compositor` target depends on `FrameCapture`

## Phase 2: Foundational (blocks every story)

- [ ] REC-001-T02 [P] `FrameCaptureFormat` (`png`, `heif`; `fileExtension`, `typeIdentifier` "public.png"/"public.heic", `alphaPolicy`: PNG `preserveCoverage`, HEIF `opaqueOverBlack`, `lossyQuality` 0.9), `FrameAlphaPolicy`, `FrameCaptureRefusal` and `FrameCaptureFailure` with notices, `FrameCaptureGate.refusal(outputLive:paused:inProgress:visualAvailable:)`, in `Packages/Compositor/Sources/FrameCapture/FrameCaptureFormat.swift`
- [ ] REC-001-T03 [P] `CapturedPixels` (`width`, `height` > 0; layouts `linearPremultipliedHalfRGBA([UInt16])`, `sRGBBGRA8TopDown([UInt8])`, `sRGBRGBA8BottomUp([UInt8])`, each count = w·h·4), `RGBA8Image`, `CapturedFrame`, in `Packages/Compositor/Sources/FrameCapture/CapturedPixels.swift`
- [ ] REC-001-T04 `FrameColorConversion`: `halfToFloat`, `linearToSRGB`, `encode8`, `rgba8(_:policy:)` per research REC-001-D3 (clamp, unpremultiply, `a8 == 0` → 0, opaque layouts swizzled/flipped with alpha 255, `hasAlpha` iff some `a8 < 255` under `preserveCoverage`), in `Packages/Compositor/Sources/FrameCapture/FrameColorConversion.swift`
- [ ] REC-001-T05 `FrameImageEncoder` (ImageIO, `#if canImport(ImageIO)`): `canEncode`, `encode(_:as:)` (sRGB `CGImage`, `last` or `noneSkipLast`, HEIF quality 0.9, no other properties), `inspect(_:)` → `FrameImageInfo` (type, width, height, hasAlpha, properties), in `Packages/Compositor/Sources/FrameCapture/FrameImageEncoder.swift`

## Phase 3: User Story 2 - The file matches its format's rules (P1)

**Goal**: dimensions, alpha presence and colors per format (the row's acceptance).
**Independent test**: fixture encoding and read-back on the host; conversion on Linux.

- [ ] REC-001-T06 [P] [US2] Conversion tests: half decode (0, 1, 0.5, subnormal, inf), sRGB at 0, 0.0031308, 0.5 (→ 188), 1, clamp of negative and > 1, unpremultiply of (0.25, 0, 0, 0.5) → (0.5 → 188, 0, 0, 128), alpha 0 → zero color, BGRA swizzle, bottom-up flip, `hasAlpha` rules; gate refusals, in `Packages/Compositor/Tests/FrameCaptureTests/FrameColorConversionTests.swift`
- [ ] REC-001-T07 [US2] Fixture encoding tests (64 × 48: opaque red, green, blue quadrants and a half-transparent white region): PNG has alpha, 64 × 48, pixels exact ±1; HEIF no alpha, 64 × 48, region centers within ±12; opaque fixture PNG has no alpha; metadata read-back has no GPS/Exif/IPTC/TIFF Make/Model/Software/DateTime, in `Packages/Compositor/Tests/FrameCaptureTests/FrameImageEncoderTests.swift`

## Phase 4: User Story 1 - Save the frame on screen as a picture (P1)

**Goal**: Save Frame on every visual, PNG or HEIF, through the Files exporter.
**Independent test**: GPU captures at known sizes; app UI test with the DEBUG folder.

- [ ] REC-001-T08 [US1] `Compositor.requestFrameCapture(_:)`: next `composite` adds an output pass (existing `cmp_output` pipeline for `rgba16Float`) into a private texture and a blit into a shared buffer; completion handler delivers `CapturedPixels` or nil; a newer request replaces (nil to the old), in `Packages/Compositor/Sources/Compositor/Compositor.swift`
- [ ] REC-001-T09 [US1] Compositor capture tests: solid and half-transparent test layers at 64 × 48 into a `bgra8Unorm_srgb` output; the capture is 64 × 48 with the expected linear premultiplied values; no capture without a request; the output with a pending capture equals the output without one (REC-001-R4); the gain applies (a full white flash after black is limited in both the output and the capture), in `Packages/Compositor/Tests/CompositorTests/CompositorCaptureTests.swift`
- [ ] REC-001-T10 [US1] `ANGLERenderer.captureNextFrame(_:)` (read framebuffer 0 after the post-pass, before the swap) and `ANGLECapturedFrame`, in `Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift`; test: a capture at the surface size after `renderFrame(present: false)`, in `Packages/ANGLERendering/Tests/ANGLERenderingTests/ANGLECaptureTests.swift`
- [ ] REC-001-T11 [US1] `FrameCaptureSource` protocol and conformances: native spectrum (framebufferOnly toggle + blit), Camera, Photo, Video (compositor), projectM (ANGLE adapter), in `Apps/projectM-iOS/Coordinators/FrameCaptureCoordinator.swift` and `Apps/projectM-iOS/Visuals/*Host.swift`
- [ ] REC-001-T12 [US1] `FrameCaptureCoordinator`: gate, one request, 1 s timeout (injected), token cancellation (visual change, pause, presentation loss), detached convert + encode, exporter document with the suggested name "Visualizer Frame <local date and time>" (REC-001-R11), notices, DEBUG `-uitestCaptureDirectory` writer and probe; `AppCoordinator` owns it and names the shown visual's source, in `Apps/projectM-iOS/Coordinators/FrameCaptureCoordinator.swift`, `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`
- [ ] REC-001-T13 [US1] UI: Save Frame control (`saveFrame`), format choice (`saveFramePNG`, `saveFrameHEIF` when encodable), `fileExporter`, notice (`frameCaptureNotice`), DEBUG probe (`frameCaptureProbe`); accessibility labels for the control, the choice and the notice (REC-001-R17), in `Apps/projectM-iOS/Views/ControlsOverlay.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`
- [ ] REC-001-T14 [US1] App unit tests: native spectrum host capture at its drawable size (opaque), Camera host capture (stub camera) at its drawable size, encode to PNG through the coordinator path, in `Apps/projectM-iOS/Tests/FrameCaptureAppTests.swift`
- [ ] REC-001-T15 [US1] UI test: Circular Spectrum, tap Save Frame, choose PNG; the probe reports `png <w>x<h> opaque` with the visual's pixel size, in `Apps/projectM-iOS/UITests/FrameCaptureUITests.swift`

## Phase 5: User Story 3 - Saving never surprises the audience or the user (P2)

**Goal**: refusals while blacked out or paused; timeouts and cancellation.
**Independent test**: coordinator tests with a fake source.

- [ ] REC-001-T16 [US3] Coordinator tests with a fake `FrameCaptureSource`: blackout not live → refusal, no request; paused → refusal; second request while busy ignored; no frame within the timeout → `noFrame`; cancel (visual change, presentation loss) drops a late frame; success hands an exporter document and clears after completion, in `Apps/projectM-iOS/Tests/FrameCaptureAppTests.swift`

## Phase 6: Polish and verification

- [ ] REC-001-T17 [P] Privacy: saved frames in `docs/privacy-policy.md` (explicit action, Files destination, Camera picture, no metadata, no copy kept) and `docs/release/app-privacy.md` (still Data Not Collected; owner confirms in App Store Connect)
- [ ] REC-001-T18 Verification: `swift test` Compositor (host and Linux shape), ANGLERendering capture test, projectM-iOSTests, FrameCaptureUITests, CameraUITests, NativeVisualUITests, OutputBlackoutUITests on the iOS 27.2 simulator; `check_compliance.py`, `validate_docs.py`, `check_privacy_manifest.py` on the Debug simulator app; PosterBoard reports counted before and after
- [ ] REC-001-T19 {device} D1 and D3 (iPadOS 26.5): PNG to On My iPhone/iPad, HEIF to iCloud Drive, both open in Files; HEIF on iOS 26.5 (quickstart, device stage 1-2)
- [ ] REC-001-T20 {device} External display active on D1 or D2: the saved frame has the display's pixel size, the projector shows nothing of the capture; blackout refusal (quickstart, device stage 3-4)

## Dependencies

T01 → T02-T05 → US2 (T06-T07) and US1 (T08-T15) → US3 (T16) → T17-T18. T19-T20 last, owner.
Parallel: T02/T03; T06 with T08/T10; T17 any time.

## Implementation strategy

MVP = Phases 1-3 (the acceptance: format rules on fixtures), then US1 end to end, then US3.

## Analysis (speckit-analyze, 2026-11-13)

No CRITICAL or HIGH findings; constitution alignment passes (I, VI, X, Privacy). Applied: R14's
presentation-loss cancellation added to T12/T16; R11's file name to T12; R17's labels to T13;
R4's "output unchanged by a pending capture" to T09. Coverage: R1-R17 and S1-S5 each map to at least
one task; S6 to T19-T20 (`{device}`).
