# Research: CMP-001 Unified Layer Protocol

Decisions are numbered CMP-001-D1… and cited by the plan, the contract and ADR-0012.

## CMP-001-D1: Where the compositor lives

- **Decision**: a new package `Packages/Compositor` with targets `Compositor` (contract, clock,
  audio context, bookkeeping, Metal compositor, composite flash guard) and `SpectrumLayers`
  (adapters for VIS-001/VIS-002), one library product.
- **Rationale**: the roadmap's proposed layout names `Compositor/`. Later layers (photos, video,
  camera, text) must not depend on the spectra, and the spectra must not depend on the compositor
  (they are also drawn straight to the screen by the app host), so the adapters sit in their own
  target that depends on both. One product keeps CI's one-scheme-per-package rule.
- **Alternatives**: a target inside `VisualGenerators` (rejected: it would make every visual depend
  on compositor types and put media layers in a "generators" package); the app (rejected: not
  testable on Linux, couples the boundary to UIKit).

## CMP-001-D2: Picture format, color space, orientation

- **Decision**: `rgba16Float`, linear light, sRGB/Rec. 709 primaries, D65, premultiplied alpha, row
  0 at the top (Metal), `.private` storage, usage render target + shader read + shader write, one
  picture per layer at the output size. The output may be `bgra8Unorm_srgb` (the screen; hardware
  encodes on write), `rgba16Float`, `bgra8Unorm` or `rgba8Unorm` (tests read these back; written
  values are linear).
- **Rationale**: blending is only correct on linear premultiplied values; 8-bit linear bands;
  16-bit float is what the bloom already uses internally (ADR-0010) and what `FlatShapePass`
  supports. Premultiplied "over" is `out = src + dst × (1 − src.a)`, one fixed-function blend state
  (`one`, `oneMinusSourceAlpha`).
- **Alternatives**: `bgra8Unorm_srgb` layers (blending in Metal's sRGB targets is linearized by the
  hardware but storage precision is 8-bit and a source writing raw values would be wrong);
  `rgba32Float` (twice the memory, not needed).

## CMP-001-D3: Frame clock and audio context

- **Decision**: the compositor's caller passes the frame's presentation time (monotonic
  nanoseconds; the display link's `targetTimestamp` in the app later) and an audio context. A
  `LayerFrameClock` derives: frame number (0, 1, 2… per `composite` call that renders), duration
  (0 on the first frame; `(t − previous) / 1e9` clamped to 0…0.1 s, FX-019's clamp), and replaces a
  time earlier than the previous one with the previous one. `LayerAudioBuffer` preallocates 128
  bands and 64 events; `update(from: AnalysisSubscription)` copies the latest frame with
  `latestFrame(into:capacity:)` and drains events with `nextEvent()` (no allocation, unlike
  `drainEvents()`), keeping the newest 64 in a ring and counting the rest as dropped. The context
  exposes `UnsafeBufferPointer`s valid for the duration of the call only.
- **Rationale**: explicit, deterministic inputs (the observable behavior); one clock for all layers;
  no layer calls the system clock or the bus. The 0.1 s clamp matches FX-019 so a stall cannot
  jump animations or open a flash window early.
- **Alternatives**: layers subscribe to the bus themselves (rejected: per-layer subscriptions, a
  layer could read audio at another moment than its neighbors, Constitution VI); arrays in the
  context (rejected: per-frame allocation).

## CMP-001-D4: Flash safety on the composite

- **Decision**: `CompositeFlashGuard` ports FX-019's envelope rule (FlashEnvelope.swift, the same
  rule as CFlashLimiter's GLSL) to one Metal compute kernel: one threadgroup of 16 threads, each
  measuring one tile of the 4 × 4 grid with 16 × 16 samples (CFlashLimiter's sample pattern;
  luminance 0.2126 R + 0.7152 G + 0.0722 B and redness max(R − G − B, 0) on linear premultiplied
  values, i.e. over black), then thread 0 computes the whole frame (mean of the tiles), the 34
  ceilings, the gain (closed form min(ceiling / level)) and commits the shown values to the state in
  a private buffer (float32, so no 16-bit packing). The output pass multiplies RGB by the gain read
  from that buffer. No CPU read-back; deterministic; history kept across pauses, `reset()` for a
  new scene. Layers that limit themselves keep doing so (gains ≤ 1 only dim).
- **Rationale**: the only place that sees the stacked picture; GPU-only, as FX-019-D4 chose for
  projectM (a read-back would stall every frame). Float state removes the GL port's 8-bit packing
  error, so the GPU gain matches FlashEnvelope's within 1e-4.
- **Alternatives**: CPU read-back of the composite (stall, one-frame latency would make it unsafe);
  per-layer only (layers out of step add up to a strobe).

## CMP-001-D5: projectM spike (iOS 27.2 simulator, iPhone Air, 2026-11-13)

`ClientBufferSpikeTests` (ANGLERendering), all four passed in 0.38 s:

- `EGL_VENDOR` "Google Inc. (Apple)", `EGL_VERSION` "1.5 (ANGLE 2.1.1 git hash: 29d18232e803)" (the
  pinned commit, `Build/ANGLEFrameworks/ANGLE.json`).
- Client-buffer and sync extensions reported at run time: `EGL_KHR_image EGL_KHR_image_base
  EGL_KHR_fence_sync EGL_KHR_wait_sync EGL_ANGLE_iosurface_client_buffer
  EGL_ANGLE_metal_texture_client_buffer EGL_KHR_reusable_sync
  EGL_ANGLE_metal_create_context_ownership_identity EGL_ANGLE_metal_shared_event_sync
  EGL_ANGLE_metal_commands_scheduled_sync`. `EGL_BIND_TO_TEXTURE_TARGET_ANGLE` = `0x305F`
  (`EGL_TEXTURE_2D`).
- **Metal texture as EGL image** (`eglCreateImage(EGL_METAL_TEXTURE_ANGLE)` on a `bgra8Unorm`
  texture from `MTLCreateSystemDefaultDevice()`, `glEGLImageTargetTexture2DOES`, framebuffer
  complete): works; a scissored GL clear read back through Metal is exact (128, 0, 0, 128 and 0, 0,
  255, 255).
- **IOSurface as pbuffer** (`eglCreatePbufferFromClientBuffer(EGL_IOSURFACE_ANGLE)`, `GL_BGRA_EXT` /
  `GL_UNSIGNED_BYTE`, plane 0, target `EGL_TEXTURE_2D`; Metal texture on the same IOSurface): works,
  same pixels.
- **Row order**: GL row 0 (the picture's bottom) is Metal row 0 (the top) in both paths: a layer
  must flip vertically when it samples an ANGLE picture.
- **Synchronization**: `eglCreateSync(EGL_SYNC_METAL_SHARED_EVENT_ANGLE)` with a caller's
  `MTLSharedEvent` and value 7, then `glFlush`; a Metal command buffer that waits for value 7
  completes and the event's `signaledValue` ≥ 7. GPU-to-GPU ordering without `glFinish`.
- **Decision**: the projectM layer uses the Metal-texture image (the layer owns a `bgra8Unorm`
  texture; projectM renders into a GL framebuffer over it with `renderFrame(toFramebuffer:)`, the
  call the warm-up already uses) and shared-event sync; the IOSurface path is the documented
  alternative. A Metal pass flips, decodes sRGB to linear and writes opaque premultiplied pixels into
  the compositor's picture.
- **Not proven here** (simulator ≠ device): the device GPU's behavior and the cost per frame
  (`{device}`, CMP-001-T20). The texture must belong to ANGLE's Metal device; on iOS
  `MTLCreateSystemDefaultDevice()` returned it (ANGLE validates `texture.device`; a mismatch fails
  `eglCreateImage` with `EGL_BAD_ATTRIBUTE`, which the layer reports as unavailable).

## CMP-001-D6: Fallback and ownership

- **Decision**: the compositor owns every picture. A layer declaring *last good frame* gets two
  pictures: it renders into the one not holding its last success; on success the roles swap. A
  *transparent* layer gets one. `LayerSlots` (CPU) holds the rule so it is tested on Linux. A
  thrown `LayerSourceError` means "do not show what this frame drew". A preparation failure marks the
  layer unavailable until the next size change or `retryUnavailableLayers()`.
- **Rationale**: a source can fail half-way through encoding; the double picture guarantees the
  last good frame survives. Typed throws (`throws(LayerSourceError)`) allocate nothing.
- **Alternatives**: copy the good frame each success (a blit per frame); trust the source to encode
  nothing on failure (VIS-001's rule, but unverifiable for arbitrary sources).

## CMP-001-D7: Hooks for CMP-002…005

- **Decision**: `LayerCompositeSettings` (opacity 0…1, blend mode enum with only `.normal`,
  2D affine transform) is read once when the compositor is built; anything but opacity 1, normal
  and identity throws `CompositorError.unsupportedCompositeSettings` (not silently ignored). The
  layer list is an array fixed at init; CMP-002 adds editing.

## CMP-001-D8: The projectM layer's own flash limiting

- **Decision**: the full-screen `ANGLERenderer` keeps its GL post-pass; the projectM layer does not
  run it (its pictures reach the screen only through the compositor, whose guard bounds the
  composite). The spectra keep their own envelope and Reduce-flashing slew.
- **Rationale**: one bound on the final picture is the guarantee; duplicating the GL pass inside the
  layer would add a GPU pass for no extra safety.
