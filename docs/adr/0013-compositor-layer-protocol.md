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

## Amendment: CMP-003 opacity per layer (2026-11-13)

Decided by Claude under owner rule 4 (feature CMP-003, `specs/043-cmp-003-opacity-per-layer/`,
research CMP-003-D1 to D9, contract `contracts/layer-opacity.md`). It lifts CMP-002's opacity
restriction; blend modes and transforms stay refused until CMP-004 and CMP-005.

1. **Opacity in the composite pass.** `cmp_over` multiplies the sanitized premultiplied picture
   (colour and alpha) by the layer's opacity, passed per draw with `setFragmentBytes` (no buffer
   per frame); the blend state is unchanged. × 1.0 is exact, so opacity 1 is bit-identical to the
   CMP-002 output. A layer whose shown opacity is exactly 0 is not drawn (the output equals the
   stack without it) but keeps rendering and stays prepared.
2. **Stored values clamp, fade requests refuse.** `LayerCompositeSettings` keeps CMP-001's rule
   (clamped to 0…1, non-finite reads 1), so `apply` never fails for opacity; a fade request with a
   non-finite target or a negative or non-finite duration throws `LayerOpacityError`. The
   compositor accepts `isSupportedByCompositor` settings (normal blend, identity transform).
3. **Fades.** The entry's opacity is the target. `apply(_:opacityTransition:makeLayer:)` (default
   `.immediate`) fades each kept layer whose opacity changed from the opacity shown last, with a
   linear or ease-in-out (smoothstep) curve; new layers start at their opacity. Each layer's
   `LayerOpacityAnimator` (CPU, Linux) advances by the frame clock's clamped frame durations: no
   wall clock, no jump after a stall, exact target at the end. `LayerStack.setSettings(_:of:)`
   changes an entry's settings. The helper is local, not ParameterGraph's `LinearMapping`, to keep
   the core target's dependencies.
4. **Flash safety.** Opacity changes the composite the guard measures and never resets its
   history, so opacity strobes are limited like any other (30 Hz test with Reduce flashing on).
5. **Not here.** No `layer.<id>.opacity` parameter (MOD-001 IDs are catalog-stable; layer IDs are
   runtime numbers): the MOD and UIX rows expose opacity. The device cost is covered by
   CMP-002-T15.

## Amendment: CMP-005 transform controls (2026-11-13)

Decided by Claude under owner rule 4 (feature CMP-005, `specs/046-cmp-005-transform-controls/`,
research CMP-005-D1 to D6, contract `contracts/layer-transform.md`). It lifts the transform
restriction of decision 5; blend modes stay refused until CMP-004.

1. **A parametric transform.** `LayerTransform` (target `Compositor`, CPU, builds on Linux) replaces
   CMP-001's unused pixel-space placeholder: a move in output fractions, a scale per layer axis
   (0.05…20, no mirroring), a rotation in radians (positive turns clockwise on screen) and an anchor
   point in layer fractions (centre by default). Move and anchor clamp to −10…10. Non-finite values
   are refused with `LayerTransformError`; finite ones are clamped (the MOD-001/CMP-003 rule);
   −0 is stored as 0.
2. **One exact matrix per output aspect.** `matrix(aspect:)` maps normalized layer coordinates to
   normalized output coordinates: stretch x by the aspect, move the anchor to the origin, scale,
   rotate, move back, un-stretch, add the move, i.e. `A = [[c·sx, −s·sy/a], [s·sx·a, c·sy]]`,
   `b = anchor + move − A·anchor`. The anchor lands at anchor + move, rotation never skews on a
   non-square output, and move 0, scale 1, rotation 0 is exactly the identity for any anchor.
3. **Saved form.** `Codable`, version 1: `{"version":1,"translation":{x,y},"scale":{x,y},
   "rotation","anchor":{x,y}}`. Every field is written; missing fields read identity values;
   another version is refused; out-of-range values clamp. JSON numbers use Swift's shortest
   round-trip form, so saving and reloading reproduces every value and the matrix bit for bit (the
   roadmap acceptance). The matrix is derived, never saved. SCN-001 embeds this object unchanged.
4. **Drawing.** Identity layers keep `cmp_over` (bit-identical to CMP-003). Other layers use
   `cmp_over_transformed` (same blend state, one more pipeline built at init): the output pixel
   centre goes through the inverse matrix in pixels (`D·M⁻¹·D⁻¹`, passed with `setFragmentBytes`,
   48 bytes), the picture is sampled bilinearly with `clamp_to_zero` (transparent outside), then
   sanitized and multiplied by opacity. Transforms act before the composite flash guard.
5. **Apply.** A kept layer takes its entry's transform from the next frame; transform-only edits
   create, prepare and release nothing. No transform animation in this row (MOD/UIX rows); group
   transforms (CMP-011) compose `LayerTransformMatrix` values; aspect fitting (CMP-006) builds on
   the matrix. The device cost is covered by CMP-002-T15.
