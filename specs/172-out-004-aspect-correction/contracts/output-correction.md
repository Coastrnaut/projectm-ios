# Contract: OUT-004 output correction

## C1 `ExternalOutputPlacement` (PresentationLifecycle)

`ExternalOutputPlacement(slotWidth:slotHeight:pixelAspectRatio:sourceAspect:fit:)` — pure, Sendable.
For Fit and Fill: `frameWidth · PAR / frameHeight == sourceAspect` (circles stay circles); Fit:
frame ≤ slot on both axes, equal on one; Fill: frame ≥ slot on both axes, equal on one. Stretch:
frame == slot, `scaleX == 1`. Invalid input: identity.

## C2 `VisualSlotView` (external role)

`correction` and `deviceShape` set by the coordinator; every layout lays the held visual out by C1
with the PAR resolved from `window.windowScene.screen.currentMode`. The device role always fills
(identity transform). `hold(_:)` resets the transform before re-placing. The slot background stays
black and the OUT-010 cover is above the visual.

## C3 `ExternalDisplayCoordinator`

`correction` (didSet → pushes to external slots unless a recording holds the placement; pushed when
the hold ends); the device slot reports its size, which is pushed as `deviceShape`.
`externalPlacementSummary` (tests, DEBUG probe): "fit=… shape=… par=… frame=W×H bars=…".

## C4 Settings

`ExternalOutputSetting` persists the three keys (absent/unknown → default; nothing stored until
changed; removed by `-uitestResetNotice`). Settings › External Display: three pickers with IDs
`externalFitPicker`, `externalShapePicker`, `externalPixelAspectPicker`.
