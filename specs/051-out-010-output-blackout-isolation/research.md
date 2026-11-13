# Research: OUT-010 Output Blackout Isolation

All decisions below are Claude's under owner rule 4 (best judgement), 2026-11-13.

## OUT-010-D1 Mechanism: an opaque cover layer set inside the tap's call

- **Decision**: Each `VisualSlotView` owns a black `CALayer` cover above every subview
  (`zPosition` high), opacity 0 while live. Black out sets the opacity of every slot's cover to 1
  inside `ExternalDisplayCoordinator.setBlackout(true)`, within `CATransaction` with actions
  disabled (a stand-alone layer would otherwise animate opacity implicitly for 0.25 s). The change
  belongs to the current transaction, which Core Animation commits at the end of the main run
  loop's turn, so the first frame the render server composites after the tap is black, whatever
  the visual's own frame loop is doing: the visual's `CAMetalLayer` presents underneath the cover.
- **"Within one frame" as a test**: frames are counted, not timed. The model's next frame after a
  blackout reports cover opacity 1 (fake frame clock); in the app, the slot's cover is opaque, with
  no animation, before `setBlackout` returns (so nothing waits for a later frame).
- **Alternatives**:
  - Hide or remove the visual view: the slot's black background shows, but removing a `CAMetalLayer`
    view and re-adding it re-lays out its drawable on restore and can show a stale drawable.
  - Make the renderer draw black (ANGLE post-pass, compositor gain): exact in pixels, but four
    pipelines change, and the black frame appears only when the visual's next frame is presented
    (up to a frame later, and never while the visual is paused or stalled).
  - `UIView.alpha` animation on the visual: animatable but implicit; same issues as removal.

## OUT-010-D2 Restore: a luminance-linear fade on frame time

- **Decision**: Restore fades the luminance factor `f` (the output's luminance as a fraction of the
  content's) from 0 to 1 linearly in frame time, over 1 s with Reduce flashing off and 4 s with it
  on. Frame times are clamped to 0…0.1 s (FX-019-R10). The cover opacity is
  `a = 1 − sRGBEncode(f)`: Core Animation blends 8-bit layers in their encoded values, so a white
  picture shows encoded `1 − a = sRGBEncode(f)` and luminance exactly `f`; darker content rises more
  slowly (the sRGB decoding curve is convex). An app test checks the blend space on the simulator
  (a half-opaque cover over white composites to encoded 0.5, not 0.73).
- **Rationale**: with Reduce flashing on, a white picture rises 0.25 per second (FX-019-R8). With it
  off there is no rise limit (FX-019-R7); 1 s is a stage-normal fade from black.
- **Alternatives**: a cut (a single large rise, repeatable by tapping); a fade in opacity (a white
  picture's luminance would rise up to 2.4 times faster at the end).

## OUT-010-D3 Restore spacing: at most one restore start per second

- **Decision**: A restore starts at least 1 s of frame time after the previous restore started; an
  earlier request waits, black (phase "restore waiting"), and the fade starts when the spacing has
  passed. Black out is always immediate, during a wait or a fade.
- **Rationale**: each blackout/restore cycle adds at most one rise and one fall transition
  (FX-019-R1). With restore starts at least 1 s apart, any 1 s window (plus the envelope's 2 ms
  tolerance) holds at most 2 rises and 2 falls: 4 transitions, within both budgets (4 with Reduce
  flashing on, 6 off). `FlashAnalysis` measures this on a white picture with the fastest tapping
  (one tap per frame).
- **Limitation (recorded in ADR-0023 decision 8)**: the cover is above the visual's own envelope,
  so the content's transitions and the cover's are not counted together. The cover only darkens
  and its rises are bounded, so the combination can exceed the budget only when the content itself
  strobes at its limit while the user toggles blackout faster than once per second. Routing the
  cover through every envelope is left to ACC-012.
- **Alternatives**: no spacing (toggling at 10 Hz is a 10 Hz strobe); a confirmation before restore
  (slower for everyone, spec Clarifications).

## OUT-010-D4 Frame driver

- **Decision**: a `CADisplayLink` on the main run loop, created when the model needs frames (a fade
  or the restore spacing) and invalidated when it does not, through a weak proxy target so the
  coordinator is not retained. Frame time is the difference of the link's timestamps (the first
  tick uses the link's `duration`). The coordinator's `advanceFrame(frameTime:)` is the one entry
  point, so tests drive it with fake frame times.
- **Alternatives**: Core Animation keyframe animation of the opacity (not observable per frame, and
  the spacing still needs a clock); the visual's frame loop (paused visuals would never restore).

## OUT-010-D5 Where the state lives

- **Decision**: `ExternalDisplayCoordinator` (app lifetime). `place()` applies the cover to every
  slot before it moves the visual, so any slot that receives the visual is already covered.
  Nothing is stored (FR-065).
