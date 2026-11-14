# Research: FX-009 Motion Feedback

Decisions by Claude under the owner's best-judgement rule (owner rule 4).

## FX-009-D1: The blend — per-channel maximum with the decayed previous frame

**Decision**: for the new composite pixel c (linear premultiplied `rgba16Float`) and the previous trails pixel p:

- if c has a NaN or infinite channel, the output is c unchanged (FX-002's output pass then maps it to 0 and counts it,
  exactly as with Trails off);
- otherwise p is sanitised (NaN/±Inf → 0, colour ≥ 0, alpha 0…1) and the output is `max(c, d·p)` per channel,
  alpha included.

`max` is taken on premultiplied values: if c.rgb ≤ c.a and p.rgb ≤ p.a then max(c.rgb, d·p.rgb) ≤ max(c.a, d·p.a), so
the result is a valid premultiplied colour. Nothing ever exceeds the brighter of the two inputs, so a still picture
converges to itself and feedback cannot run away; transparent areas become transparent again as p decays.

**Rationale**: the classic additive form `c + d·p` needs a tone map to stay bounded and still brightens a still
picture to 1/(1 − d) times its value (×44 at d = 0.977): a large, persistent brightness change and a flash risk. Max
"trails" show motion without changing a still picture at all.

**Alternatives considered**: additive with a tone map (runaway brightness, changes still pictures); a linear mix
`(1 − d)·c + d·p` (dims moving objects and blurs a still picture's changes; a moving bright object loses intensity);
screen blend (brightens stills).

## FX-009-D2: The decay model — half-life in seconds, converted per frame

**Decision**: `d = min(0.5^(Δt / h), 0.99)` with Δt the frame's duration from the compositor's frame clock (CMP-001:
0 on frame 0, clamped to 0…0.1 s, injected in tests) and h the effective half-life. Computed in `Double` on the CPU
once per frame, passed to the shader as one `Float`. The user's half-life range is 0.05…0.50 s, default 0.20 s,
step hint 0.01 s.

At 60 fps the longest length gives d = 0.977 (inside the brief's 0…0.98), at 120 fps 0.989; the 0.99 ceiling only
binds above 120 fps or on a zero-duration frame (a repeated presentation time), where it makes trails fade a little
rather than freeze. After n frames of total time T the fade is 0.5^(T/h) whatever the frame rate.

**Alternatives considered**: a raw per-frame decay slider (frame-rate dependent: a 120 Hz iPad would show trails half
as long); a hard 0.98 per-frame cap (breaks frame-rate independence at 120 Hz for lengths above 0.29 s).

## FX-009-D3: Placement — on the composite, before the grade, tone map and flash guard

**Decision**: in `Compositor.encodeFrame`, after the stack phase (or CMP-013's kept composite) and before `finish`:
one full-screen pass `cmp_trails` reads the composite and the history picture and writes the other picture of a
pooled ping-pong pair (composite size, `rgba16Float`); that picture is what `finish` receives, so FX-019's guard,
FX-003's grade, FX-002's tone map, the screen, REC-003's `encodeOutput`, REC-001's capture and CMP-014's bus
(`encodeScene` returns it) all see the trails frame. The two pictures then swap roles.

**Rationale**: safety (the guard) must judge what is shown, and grading after feedback keeps trails in linear light
with one grade per shown pixel (grading before would grade history twice).

## FX-009-D4: Reset — a flag consumed by the next frame

**Decision**: a reset sets `trailsResetPending`; the next frame's pass runs with `reset = 1`, which writes c exactly
(a half-float read and write of the same format is exact), so the shown frame is bit-identical to Trails off and the
history restarts from it. Triggers inside the compositor: `resetFeedback()` (public), `resetFlashHistory()` (a new
scene, FX-019-R11: every visual host calls it when its frame loop starts — visual switch, resume after pause or
background), `resetRenderHealth()` (PERF-014), an output size change (`allocate`), an output pixel format change in
`composite(into:)`, turning Trails on (or changing from inactive to active after a safety cap), and any frame that
did not finish. `SceneTransitionBus.show(_:)` and `transition(to:…)` reset both scenes. In the app,
`AppCoordinator.resetTrailsHistory()` is called by show cue apply (`applyShowScene`, also UIX-002's switcher),
scene reopen (`finishReopen`) and undo/redo (`applySceneInputs`).

**Alternatives considered**: clearing the history texture to transparent (the next frame would be `max(c, 0)`, not
bit-identical for negative composite values); an immediate GPU clear at reset time (needs a command buffer outside a
frame).

## FX-009-D5: CMP-013 — no composite reuse while Trails are active

**Decision**: `canReuseComposite()` returns false while Trails are active; level-1 (layer picture) reuse stays. The
stored stack composite would in fact be a correct input, but the requirement keeps time-dependent output out of the
cache entirely, and the cost is one stack pass per frame that a still scene would otherwise skip. With Trails off
the cache behaves exactly as before.

## FX-009-D6: Safety — ACC-012 caps the length; the guard measures the result

**Decision**: effective half-life = min(user, cap) with cap = 0.50 s × intensity limit when the profile caps
intensity (Reduced 0.25 s, Strict 0.125 s, Custom limit 0 → off), and at most 0.25 s when Reduce flashing is
effective (the setting, Reduce Motion fallback or a stricter flash profile); off when the cap is 0. Standard with
Reduce flashing off leaves the user's value unchanged. FX-019's guard runs on the trails frame under every profile.

**Rationale**: trails by maximum soften the dark half of a strobe (lower flash contrast) but keep bright areas on
screen longer; capping the length bounds persistence while keeping the effect usable. The guard still limits a
strobing source: a red/black strobe with trails becomes red/decayed-red, and any remaining transition above the
threshold is limited.

## FX-009-D7: Pool use and allocation

**Decision**: the pair is taken from the compositor's `TexturePool` the first active frame at a size (allocation
point), returned (fenced by the last command buffer) when Trails turn inactive (at the next frame or in the setter),
at a size change and in `deinit`. Trails off holds no picture. The per-frame block (decay, reset) is a 16-byte
`setFragmentBytes`; nothing is allocated per frame.

## FX-009-D8: Scope and parameters

**Decision**: compositor-backed visuals only (Camera, Photo, Video, Text); the native spectra with FX-001 bloom have
their own renderer and are unchanged. No zoom or rotation of the previous frame (minimal row; FX-010 can extend).
MOD-001 IDs `effect.feedback.enabled` (boolean, default false, discrete manual) and `effect.feedback.halfLife`
(continuous 0.05…0.50 s, default 0.20, step 0.01, unit seconds), in a `MotionFeedbackCatalog` beside
`ColorGradeCatalog` in the `ColorGradeParameters` target (the compositor output pass's parameters; no new target),
registered in the app scene registry and the golden renderer. Live modulation is not wired (no compositor visual
has a modulator).

## FX-009-D9: App setting and UI

**Decision**: `MotionFeedbackSetting` (keys `settings.feedback.enabled` Bool, `settings.feedback.halfLife` Double),
read rule as FX-003's (absent, non-number, NaN → default; out of range → nearest bound); `effective(clamp:)`
applies D6. Settings section "Trails" (own view, in `mediaSections` after Color): toggle `trailsToggle`, "Length"
slider `trailsLengthSlider` (ACC-005 `.accessibleParameter`, step 0.05 s, unit seconds with two decimals), readout
"0.20 s", footer naming the visuals and the safety caps. Keys join `LibrarySettingsPolicy.includedKeys` (FILE-005;
FILE-011's erase derives from it), the privacy allow-list and the UI-test reset (`MotionFeedbackSetting.allKeys`).

## FX-009-D10: GPU cost (filled in by FX-009-T10)

To be measured on the Mac (M-class GPU) with command-buffer GPU timestamps, 1170 × 2532 output, 120 frames with and
without Trails; recorded here and in the ADR.
