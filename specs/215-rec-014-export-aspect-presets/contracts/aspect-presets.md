# Contract: REC-014 aspect presets

## C1 Geometry

`RecordingGeometry(drawableWidth: dw, drawableHeight: dh, settings: s)`:

1. Source: w = dw − dw % 2, h = dh − dh % 2; nil when either < 2.
2. Limits: L = min(even(s.maxLongSide), cap.maxSide); P = cap.maxPixels.
3. Match screen: REC-003's fit to L (nearest even); then, when w'·h' > P, both sides scaled by √(P / (w'·h')) and floored to even. `cropsToFill` false.
4. Preset or custom with reduced ratio u:v: crop = (w, ⌊w·v/u⌋) when w·v ≤ h·u, else (⌊h·u/v⌋, h). Step k = 2 when u or v is odd, else 1. m = largest multiple of k with max(u,v)·m ≤ L, u·m ≤ cropW, v·m ≤ cropH, u·v·m² ≤ P. Preset: m < k → nil. Output (u·m, v·m).
5. Custom W×H: if W ≤ cropW, H ≤ cropH, max(W,H) ≤ L and W·H ≤ P → exactly W×H. Else reduced: the step-4 multiple when its long side ≥ 90% of the uniform fallback (factor f = min(L/max(W,H), cropW/W, cropH/H, √(P/(W·H))), sides ⌊·f⌋ to even, ≥ 2), otherwise the fallback.
6. `cropsToFill` = the aspect is not Match screen (with an exact ratio the fill equals a plain fit, so the rule needs no ratio test).

Invariants (tested): sides even and ≥ 2; outputWidth·outputHeight ≤ P; max side ≤ cap.maxSide; never larger than the source's crop in either dimension (no upscale).

## C2 Catalog

`RecordingQualityCatalog.availability/availabilities/resolve` and `RecordingFrameRateCatalog.availability/resolve` take `aspect: RecordingAspect = .matchScreen`; the profile settings get `aspect` and `capabilities.outputCap`; a nil geometry is `.noPicture`. `RecordingEncoderCapabilities.outputCap` defaults to `.regular`.

## C3 Writer

When the geometry is scaled, `AVVideoScalingModeKey` is `ResizeAspectFill` if `cropsToFill`, else `ResizeAspect` (REC-003 unchanged).

## C4 Notice

`RecordingRecordResolution.notice` appends "Recording at W×H: Custom size reduced to fit this device." when the plan's geometry has `reducedCustomSize` (after the profile and rate notices; all start with "Recording at ", status row X9c).

## C5 App

`RecordingQualitySetting.aspect` (kind + custom size, keys in data-model.md), `availability(kind)`, `select(kind)`, `setCustom(width:height:)` (validated), row labels "Square, 1178×1178 · HEVC · 7.5 Mb/s · 30 fps", reduced custom "Custom, Reduced to W×H on this screen · …". Settings section "Recording aspect" (identifiers `recordingAspect.<kind>`, fields `recordingAspect.customWidth/Height`), anchor `recordingAspect`, after the frame-rate section. `VideoRecordingCoordinator.Context.aspect`.
