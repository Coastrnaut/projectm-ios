# Research: OUT-009 Output Color Calibration

## D1 — Which public mechanism can colour-correct arbitrary layer content on iOS?

- Decision: none can; use each visual's existing final render pass.
- Rationale: `CALayer.filters`, `backgroundFilters` and `compositingFilter` are documented "not supported on
  iOS" (the properties exist but are ignored). An overlay layer is composited with source-over only: it can
  darken or tint (a multiply needs a compositing filter) and can never apply a power curve. SwiftUI's
  `colorEffect`/`layerEffect` shaders do not apply to UIKit-hosted platform views (`UIViewRepresentable`).
  `CAMetalLayer.colorspace` only tags content for the system's colour matching; a calibrated `CGColorSpace`
  with custom gamma and matrix is not documented as honoured by iOS's compositor for every layer type, and
  no test can read back the composited result (the simulator and `drawHierarchy` show pre-match content).
  `UIScreen` exposes brightness (device screen only) and no gamma/LUT. `drawHierarchy`/`render(in:)` per
  frame is CPU snapshotting (tens of ms at 1080p) and `render(in:)` omits Metal/GL content. A
  `CAMetalDisplayLink` gives timing, not access to other layers' pixels.
- Alternatives considered: all of the above; rejected as unsupported, unverifiable or far too slow.

## D2 — Which final passes exist, and what do they cover?

- projectM (ANGLERenderer): every frame ends in CFlashLimiter's output pass (FX-019: `texture(scene) × gain`
  in encoded values, exact sRGB decode/encode) drawn into framebuffer 0 of the window surface. Covers every
  preset; the engine is untouched.
- Compositor visuals (Camera, Photo, Video, Text hosts; projectM as a layer; MED-010 logo): `cmp_output` in
  `Compositor.composite(into:)`. Recordings use `encodeOutput`, captures `encodeCapture`, both separate.
- Native spectra (NativeSpectrumHost): the generator or bloom draws straight into the drawable; the recording
  blits the drawable. No shared pass → not covered (adding one is an extra full-screen pass per generator
  path; out of this row's scope, stated in the editor).
- GLESRenderer: the fallback when no EGL context can be created; shares CFlashLimiter but nothing routes
  calibration to it → not covered (stated).

## D3 — Transfer function and colour space

- Decision: on the display-encoded (sRGB) value e ∈ [0, 1]: e' = clamp(trim_c × e^(1/γ), 0, 1); γ ∈ 0.5…2.5,
  trims ∈ 0.5…1.5, alpha unchanged; identity (γ = 1, trims 1) is a bypass.
- Rationale: display calibration curves operate on the signal the display receives; projectM's pass already
  holds encoded values. The compositor's target is `bgra8Unorm_srgb`, so its pass encodes (exact sRGB curve),
  applies, decodes and lets the target re-encode; the round trip is within one 8-bit step. FX-003's gamma
  convention (exponent 1/γ, above 1 brightens) keeps one meaning of "gamma" in the app.
- Alternatives: linear-light gains (a trim then does not match a display's per-channel drive); a 3×3 matrix
  or LUT (beyond the row; harder to adjust by hand).

## D4 — Where in the pass, relative to the flash envelope?

- Decision: last, after the envelope's gain and FX-002's tone map.
- Rationale: the envelope judges the intended picture (it must not depend on the display); calibration is a
  fixed monotonic per-channel curve that compensates the display's response, so it adds no transitions.

## D5 — Keeping recordings, captures and the device uncalibrated

- Compositor: only the screen pass of `composite(into:)` uses the calibrated pipeline; `encodeOutput`,
  `encodeCapture` and the bus are unchanged. The visual on the device slot gets the identity.
- projectM: REC-001 reads framebuffer 0 after the pass; with a pending capture and a non-identity calibration
  the output step is redrawn uncalibrated (same envelope state, no second update), read, then redrawn
  calibrated before the swap. projectM is not recordable (REC-003 row), so nothing else reads it.
- Thumbnails and scene previews use their own renderers/compositors (never the slot's visual) → unaffected.

## D6 — Routing

- Decision: `DisplayCalibrationReceiver` (main-actor protocol in Compositor) adopted by ANGLE's
  `MetalLayerView` and the app's `NativeSpectrumLayerView` (accepts only when its host installed a handler:
  compositor hosts do, the native spectrum host does not). `VisualSlotView` sets it on held views (external:
  the slot's calibration; device and on removal: identity), like OUT-003's display-scale override.
- Alternatives: a custom `UITrait` (works, but every host would need trait-change registration and per-frame
  reads); the coordinator reaching into AppCoordinator's renderers (couples OUT routing to visual creation).
