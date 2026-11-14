# ADR-0051: Motion Feedback ("Trails") Runs on the Composite Before the Grade and the Flash Guard, and Every Scene Change Resets It

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-009 (`specs/130-fx-009-motion-feedback`)
- **Constitution**: VI (modular boundaries: the pass inside `Packages/Compositor`), VII (no per-frame allocation),
  VIII (upstream fidelity: off is bit-identical), X (evidence-based quality); photosensitivity (FX-019, ACC-012)
- **Builds on**: ADR-0013 (CMP-001 compositor), ADR-0040 (CMP-013 caching: amended, no composite reuse while Trails
  are active), ADR-0042 (CMP-014 bus: a cut or transition start resets the scenes' trails), ADR-0047 (FX-002 tone
  map), ADR-0049 (ACC-012 safety clamp), ADR-0050 (FX-003/FX-004 grade)
- **Number**: 0051, the next free number after FX-003's 0050; 0015, 0016, 0025, 0026, 0031, 0045 and 0046 stay
  unused.

## Context

The roadmap row FX-009 asks to "blend previous frame with decay and reset on scene changes", with the acceptance
"reset clears prior scene content in the first new frame". The compositor-backed visuals (Camera, Photo, Video, Text)
build each frame from a cleared composite, then FX-019's guard and the output pass (FX-003 grade, FX-002 tone map,
× gain) serve the screen, external display, REC-003 recording, REC-001 capture and CMP-014's bus. Nothing kept a
previous frame. FX-010 ("Echo feedback", later) builds on this row.

## Decision

1. **Blend: per-channel maximum with the decayed previous frame** (research FX-009-D1):
   `out = max(composite, d × previous)` on linear premultiplied values, alpha included (stays a valid premultiplied
   colour). It never exceeds the brighter input, so a still picture is unchanged and feedback cannot run away;
   additive feedback (`c + d·p`) was rejected because it brightens stills up to 1/(1 − d) and needs a tone map to
   stay bounded. A non-finite composite pixel is passed through unchanged (FX-002 maps and counts it as before); the
   history is sanitised, so nothing non-finite spreads. No zoom or rotation of the previous frame in this row.
2. **Decay: a half-life in seconds** (D2): `d = min(0.5^(Δt / h), 0.99)` with Δt the frame clock's duration (0…0.1 s).
   User range 0.05…0.50 s, default 0.20 s; at 60 fps the longest gives 0.977 per frame, at 120 fps 0.989, and the
   fade per second is the same at any frame rate (measured 0.4976 at 60 fps and 0.4961 at 120 fps after one
   half-life on the GPU). The ceiling binds only above 120 fps or on a 0 s frame.
3. **Placement: on the composite, before the grade, tone map and flash guard** (D3). After the stack phase (or a kept
   composite), one full-screen pass `cmp_trails` reads the composite and the history and writes the other picture of
   a pooled ping-pong pair (composite size, `rgba16Float`). That frame is what the guard measures and every output
   (and `encodeScene`) receives; grading happens once per shown pixel.
4. **Reset rule** (D4): a reset flag makes the next frame write the composite unchanged — bit-identical to Trails off
   — and restarts the history. Raised by `resetFeedback()`; `resetFlashHistory()` (a new scene, FX-019-R11: every
   visual's frame-loop start, so a visual switch and a resume); `resetRenderHealth()` (PERF-014); an output size
   change; an output pixel-format change; turning Trails on (inactive → active); any frame that did not finish;
   `SceneTransitionBus.show(_:)` (another scene) and `transition(to:…)` (both scenes). The app calls
   `resetFeedback()` on every compositor-backed visual after a show cue apply (also UIX-002's switcher), a scene
   reopen and an undo/redo. Slideshow slides and media changes inside a visual are not scene changes.
5. **CMP-013** (D5): no composite reuse (level 2) while Trails are active; layer pictures (level 1) may still be
   reused. Trails off: caching exactly as before.
6. **Safety** (D6): ACC-012's intensity limit caps the half-life at limit × 0.50 s (Reduced 0.25 s, Strict 0.125 s,
   a Custom limit of 0 turns Trails off) and Reduce flashing caps it at 0.25 s; the stricter cap wins. The guard
   measures the trails frame under every profile: on a 5 Hz white/black strobe with trails it still lowered its
   gain (to 0.80 with Standard 0.2 s trails, 0.58 with Strict-capped trails). Max-blend trails soften dark frames
   (lower flash contrast) but hold bright areas longer, hence a cap rather than removal.
7. **Resources** (D7): inactive Trails hold no picture and add no pass (output bit-identical to before FX-009); the
   pair is taken from the compositor's `TexturePool` on the first active frame at a size and returned, fenced by the
   last command buffer, when Trails turn inactive, at a size change and in `deinit`. Per frame: one 16-byte
   `setFragmentBytes`, no allocation.
8. **Scope and settings** (D8, D9): compositor-backed visuals only (the native spectra with FX-001 bloom and projectM
   are unchanged). One global setting (`settings.feedback.enabled`, `settings.feedback.halfLife`; backed up, erased
   with Settings, allow-listed), Settings → Trails (toggle, ACC-005 "Length" slider, help), MOD-001 IDs
   `effect.feedback.enabled` and `effect.feedback.halfLife` (registered; modulation not wired yet).

## Consequences

- With Trails on, a still scene costs one stack pass per frame that CMP-013 would otherwise skip, plus the trails
  pass; measured on the Mac (Apple-silicon GPU, 1170 × 2532, median of 50 frames, best of 3): frame GPU time 0.167 ms
  off, 0.183 ms on (about 0.02 ms for the pass). The device frame rate is checked in the last stage (FX-009-T18,
  `{device}`).
- The first frame after any scene change has no prior-scene content (FX-009-S1, bit-identical in both output
  formats for every trigger).
- FX-010 (echo feedback) can add bounded history buffers behind the same reset rule.
