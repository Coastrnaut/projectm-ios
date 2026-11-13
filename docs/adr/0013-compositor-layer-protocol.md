# ADR-0013: Compositor and the unified layer protocol

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4; feature CMP-001)
- **Date**: 2026-11-13
- **Spec**: `specs/029-cmp-001-unified-layer-protocol/` (research CMP-001-D1 to D8, contract
  `contracts/layer-source.md`)
- **Constitution**: I, VI, VII, VIII, X

## Context

The roadmap's render boundary (architecture item 2) asks for a frame-source/compositor boundary
that can consume projectM, native generators, photos, video, camera and text, with an explicit color
space, alpha convention, timebase, resource ownership and safe fallback. Before CMP-001 each visual
drew straight to the screen: the native spectra through `NativeSpectrumHost` (ADR-0009, ADR-0010),
projectM through ANGLE into a window surface on a `CAMetalLayer` (ADR-0003). The audit's
architecture finding: sharing projectM's frame with Metal needs ANGLE to render into a texture
Metal can sample, unproven for the pinned build.

## Decisions

1. **Package.** `Packages/Compositor`: target `Compositor` (contract, clock, audio context,
   bookkeeping, Metal compositor, composite flash guard; depends on `AnalysisFeatures` and
   `FlashSafety` only) and target `SpectrumLayers` (VIS-001/VIS-002 adapters). The projectM layer is
   target `ProjectMLayer` in the `ANGLERendering` package. Nothing in `Compositor` imports projectM,
   ANGLE, capture or the app (Constitution VI).
2. **Pictures.** Every layer draws a whole compositor-owned picture: `rgba16Float`, linear light,
   sRGB/Rec. 709 primaries, D65, premultiplied alpha, row 0 at the top. The compositor creates
   pictures once per output size; sources may create working resources only in `prepare`. Output
   encoding (8-bit sRGB for the screen) happens only in the final pass.
3. **Context.** Each frame every layer receives the same `LayerFrameContext` (monotonic
   presentation time, frame number, duration clamped to 0…0.1 s, output size and scale, Reduce
   flashing) and `LayerAudioContext` (the latest ANL-016 frame, its bands, events since the previous
   frame, bounded at 128 bands and 64 events, as plain values valid for the call). Layers never ask
   the engine, the capture system, the bus or the clock.
4. **Failure.** A layer declares `.transparent` or `.lastGoodFrame`; a thrown typed error shows the
   fallback for that frame and is reported per layer; last-good layers render into a second picture
   so a failed frame never overwrites the good one; a failed `prepare` makes the layer unavailable
   until the next size change or an explicit retry. Other layers always composite.
5. **Composition.** A fixed, ordered list, premultiplied "over" (`one`, `oneMinusSourceAlpha`) onto
   transparent, accumulated in `rgba16Float`. Opacity, blend mode and transform are part of the
   layer's settings but only identity values are accepted until CMP-003, CMP-004 and CMP-005.
6. **Flash safety on the composite.** FX-019's envelope (ADR-0011) runs on the finished composite
   every frame, as a Metal compute port of `FlashEnvelope` (16 tiles × 256 samples, the whole frame
   as the tile mean, float state, no read-back), then the output pass applies the gain. A stack of
   layers therefore cannot add up to a strobe. The spectra keep their own envelope and
   Reduce-flashing slew (gains only dim); the full-screen projectM renderer keeps its GL post-pass;
   the projectM layer relies on the composite bound.
7. **projectM as a layer.** The spike on the iOS 27.2 simulator (research CMP-001-D5) found
   `EGL_ANGLE_metal_texture_client_buffer`, `EGL_ANGLE_iosurface_client_buffer` and
   `EGL_ANGLE_metal_shared_event_sync` in the pinned build's extension string (ANGLE 2.1.1,
   29d18232e803) and both client-buffer paths round-trip exact pixels; GL row 0 lands in Metal row
   0, so the layer flips. `ProjectMLayerSource` owns an EGL context and engine, renders into a GL
   framebuffer over its own `bgra8Unorm` Metal texture (EGL image), lets ANGLE signal an
   `MTLSharedEvent` that the compositor's command buffer waits for (no CPU wait), and converts the
   picture to the layer format. Extensions are checked at run time; a missing one makes the layer
   unavailable with the extension's name.
8. **App unchanged.** The app does not use the compositor in this row; wiring it into the screen
   (and replacing `NativeSpectrumHost`'s direct drawing) is a later row, after the device checks.

## Consequences

- Later rows (CMP-002…015, MED, CAM, OUT, REC, SCN) add layers by conforming to `LayerSource`; a
  recording or external display output receives the same composited frame (architecture item 6).
- Per frame cost: one pass per layer, one over pass per layer, one 16-thread dispatch and one output
  pass; the projectM layer adds a flip/decode pass. Device cost is unmeasured (CMP-001-T20,
  `{device}`).
- A spectrum layer is limited twice (its own envelope, then the composite's); the composite gain is
  1 for a frame the layer already bounded unless other layers add light.
- Simulator evidence only so far; the client-buffer paths and shared-event sync must be rechecked on
  D1-D3 before the app composites projectM.

## Amendment: CMP-002 ordered layer stack (2026-11-13)

Decided by Claude under owner rule 4 (feature CMP-002, `specs/040-cmp-002-ordered-layer-stack/`,
research CMP-002-D1 to D8, contract `contracts/layer-stack.md`). It replaces this ADR's "fixed list
of layers" with an editable stack; every other decision stands.

1. **A value stack.** `LayerStack` (target `Compositor`, CPU, builds on Linux) holds ordered
   entries, **index 0 the bottom**: a stable `LayerInstanceID` (from a per-stack counter, never
   reused), a `LayerDescriptor` (a `LayerKind` and numeric parameters) and the entry's
   `LayerCompositeSettings`. Add at an index, remove, duplicate (directly above, new ID, equal
   descriptor and settings) and move either succeed or throw a typed `LayerStackError` and leave
   the stack unchanged. Equality compares entries.
2. **Limits.** At most 8 layers (each holds one or two drawable-size pictures and costs two draws
   per frame). A kind may cap its instances: `.camera` allows one, so no stack opens a second
   capture session (sharing one session between camera layers was rejected for now).
3. **Kinds live with their layers.** `.camera` in `CameraLayer`, `.circularSpectrum` and
   `.linearSpectrum` in `SpectrumLayers`; Compositor names none of them. The caller's factory maps
   kinds to live layers.
4. **Apply between frames.** `Compositor.apply(_:makeLayer:)`: an equal stack is a no-op; layers
   whose ID remains keep their object, pictures, slots and last good frame at their new index; the
   factory runs only for new IDs and new layers are prepared at apply when the size is known (a
   third allocation point beside the first frame and a resize); removed IDs are released with
   nothing called on them (owners stop outside resources such as the camera). Any refusal
   (non-identity settings until CMP-003/004/005, a factory error, one object for two entries)
   leaves the previous stack applied. The flash guard's history survives an apply.
5. **App.** The Camera visual builds its camera + circular spectrum stack through `LayerStack`;
   behaviour is unchanged. No user-facing editor: CMP-015 (layer inspector) and the editing UI rows.
   Per-layer frame cost of a 4-layer stack on D1-D3 is CMP-002-T15 `{device}`.
