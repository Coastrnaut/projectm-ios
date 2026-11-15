# Tasks: UIX-012 Touch Color Sampler

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/color-sampler.md](contracts/color-sampler.md)

## Phase 1: Foundational (pure mapping and pixel reading)

- [ ] UIX-012-T01 [P] Add `PreviewFit`, `PreviewPixel` and `PreviewPixelMapping` (view size, split scale/origin, fit, picture size, pixel aspect; `pixel(at:)` per contract C1: reject non-finite, outside the split output rect, or outside the fit rect; floor with the far edge clamped) in `Packages/Compositor/Sources/FrameCapture/PreviewPixelMapping.swift` (R4, D2, D3)
- [ ] UIX-012-T02 [P] Add `SampledColor` (straight linear RGBA 0…1, `sRGB` components, spoken text "red R%, green G%, blue B%" in whole sRGB percents) and `CapturedPixels.sampledColor(x:y:)` for all three layouts (halves: clamp, alpha 0 → black, min(c, a)/a; 8-bit sRGB decoded, bottom-up rows flipped) in `Packages/Compositor/Sources/FrameCapture/CapturedPixelSample.swift` (R6, D4)
- [ ] UIX-012-T03 Tests in `Packages/Compositor/Tests/FrameCaptureTests/PreviewPixelMappingTests.swift`: stretch at Retina scale 3, fit with letterbox and pillarbox (bar taps rejected), fill (crop), split-scaled preview (outside rejected), non-square pixel aspect, far-edge clamp; sample conversions for each layout, premultiplied → straight, transparent → black, HDR clamp (S2)

## Phase 2: User Story 1 — pick a colour from the picture (P1, MVP)

- [ ] UIX-012-T04 [US1] GPU acceptance in `Packages/Compositor/Tests/CompositorTests/ColorSampleCompositorTests.swift`: a grid of distinct premultiplied colours (some with alpha < 1) through the real compositor at 64 × 48, captured with `requestFrameCapture`; taps at chosen view points for stretch at scale 2, a split placement, and fit in a wider view; the sampled straight colour equals the pattern's at the mapped pixel within 1/255 in linear and in 8-bit sRGB (S1, acceptance)
- [ ] UIX-012-T05 [US1] `ColorSampleTarget` and `ColorSamplerCoordinator` (begin/refusals, one in-flight request with a token, injected timeout, map with the captured size, write between `endCoalescing()` and `recordStep(label: "Sample <name>")`, unchanged colour records nothing, alpha kept, announce on `.parameter`, cancel, end after a write) in `Apps/projectM-iOS/Coordinators/ColorSamplerCoordinator.swift` (R2, R5-R9, R11, C3)
- [ ] UIX-012-T06 [US1] Wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+ColorSampler.swift` (context: capture source, external, blackout, paused, lock; the three MED-009 text targets in sRGB; Settings closed while sampling as a sheet and reopened after; DEBUG `-uitestColorSampleFixture r,g,b` source) plus one lazy property in `AppCoordinator.swift` (R2, R3, D7)
- [ ] UIX-012-T07 [US1] Views in `Apps/projectM-iOS/Views/ColorSamplingViews.swift`: `EyedropperButton` (`eyedropper.<key>`, label "Pick <name> from the picture", value the spoken colour), `ColorSamplingLayer` (window-coordinate `SpatialTapGesture`, banner with message and Cancel, escape action), `SplitPlacementReporter`; small edits in `VisualizerView.swift` (layer above the tap target, reporter in the backdrop, split availability) and `SettingsView.swift` (eyedroppers by Color, Outline color, Box color) (R1, R3, R8, C4)
- [ ] UIX-012-T08 [US1] App unit tests in `Apps/projectM-iOS/Tests/ColorSamplerTests.swift` with a fake capture source and the real `SceneHistoryCoordinator`: a tap writes the expected sRGB text colour (alpha kept) and is one undo step "Sample Text color"; Undo restores the previous colour exactly, Redo re-applies; Cancel records nothing; out-of-picture tap rejected and mode kept; nil frame and timeout keep mode with the failure text; refusals (no source, external, blacked out, paused, locked); announcement text (S3)
- [ ] UIX-012-T09 [US1] UI test `Apps/projectM-iOS/UITests/ColorSamplerUITests.swift`: Text visual, fixture colour, tap the eyedropper by Color, tap the preview, Settings returns and `eyedropper.textColor` reads the fixture colour; under 30 s (S4)

## Phase 3: User Story 2 — sample in the split editor (P2)

- [ ] UIX-012-T10 [US2] The split placement reaches the sampler (reporter) and the coordinator maps window points through it; a unit test in `Apps/projectM-iOS/Tests/ColorSamplerTests.swift` samples with a scaled placement and rejects a tap beside the scaled output (US2 scenarios 1, 2)

## Phase 4: Polish

- [ ] UIX-012-T11 Add the new app files to `scripts/check_status_events.py`; repo checks (compliance, docs, motion, permission catalog, status events, script tests); privacy manifest and network symbol checks on the Debug app; type-check budget on new and changed files; Compositor package tests on the host; no new UserDefaults key (R10)
- [ ] UIX-012-T12 Mark the spec Implemented; final report
- [ ] UIX-012-T13 {device} On D1: sample a live visual (Text visual over a spectrum) and compare by eye; with VoiceOver hear "<name> set to …" and cancel with the escape gesture; on D2 sample in the split editor

## Dependencies

T01, T02 → T03, T04 → T05 → T06 → T07 → T08, T09, T10 → T11 → T12; T13 needs a device and a person. No new UserDefaults key, so no key list changes.

## Parallel opportunities

T01 and T02 are separate files; T04 (package) can run while T05 is written.

## Implementation strategy

MVP is Phase 1 + US1 (T01-T09); US2 adds a test over the same code path.
