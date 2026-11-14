# Contract: Motion Feedback (FX-009)

## Compositor API (`Packages/Compositor`)

- `struct MotionFeedback: Sendable, Equatable, Codable` — `isEnabled`, `halfLifeSeconds`; `static let off`,
  `halfLifeRange = 0.05...0.50`, `halfLifeStep = 0.01`, `defaultHalfLife = 0.20`, `longestHalfLife = 0.50`,
  `reduceFlashingHalfLife = 0.25`, `maximumDecay = 0.99`; `clamped`, `isActive`, `decay(frameDuration:)`,
  `limited(by:)`, `static blend(current:previous:decay:reset:)`.
- `Compositor.motionFeedback: MotionFeedback` (set between frames; from the next frame).
- `Compositor.resetFeedback()` — the next frame shows the composite only.
- `Compositor.resetFlashHistory()` and `resetRenderHealth()` also reset the trails (a new scene).
- `Compositor.trailsFrames`, `trailsResets`, `holdsTrailsPictures` — tests, diagnostics.
- `SceneTransitionBus.show(_:)` and `transition(to:spec:reduceMotion:)` call `resetFeedback()` on the scenes involved.

## Shader

- `cmp_trails(composite [[texture(0)]], history [[texture(1)]], constant CMPTrails &t [[buffer(0)]])`: research
  FX-009-D1 and D4; per-pixel `read`, no sampling.

## Guarantees

1. Trails inactive: no pass, no picture held, output bit-identical to before FX-009; CMP-013 unchanged.
2. Reset frame: the shown frame is bit-identical to the Trails-off frame of the same scene.
3. Trailing frame: equals `MotionFeedback.blend` of the composite and the previous trails frame with
   `decay(frameDuration:)`, within half-float rounding.
4. FX-019's guard, FX-003/FX-004's grade, FX-002's tone map, REC-001, REC-003 and CMP-014 see the trails frame.
5. No composite reuse (CMP-013 level 2) while active.
6. Pool: two checkouts while active at a size, zero while inactive; returned at disable, size change and `deinit`.

## App

- Keys `settings.feedback.enabled` (Bool), `settings.feedback.halfLife` (Double) in `MotionFeedbackSetting.allKeys`,
  FILE-005 included keys and the privacy allow-list.
- Settings → Trails: toggle `trailsToggle`, slider `trailsLengthSlider` (label "Length", visible while on), readout
  `trailsLengthSliderValue` ("0.20 s").
- MOD-001 IDs `effect.feedback.enabled`, `effect.feedback.halfLife`.
- `AppCoordinator.resetTrailsHistory()` after show cue apply, scene reopen and undo/redo; the hosts' loop start resets
  through `resetFlashHistory()`.
