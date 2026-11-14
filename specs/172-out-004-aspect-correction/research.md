# Research: OUT-004 Aspect Correction

## OUT-004-D1: Where the correction lives

Decision: in the external `VisualSlotView`, as the visual view's `bounds`, `center` and a
`CGAffineTransform(scaleX: 1/PAR, y: 1)`. Rationale: every visual (ANGLE renderer view, compositor,
native spectrum, Camera, Photo, Video, Text) sizes its drawable from its view's bounds and display
scale (OUT-001-D3), so placing the view corrects them all at once; the transform does not change
`bounds`, so drawables are laid out at the corrected size and Core Animation applies the horizontal
scale when compositing. No render pass, no change to projectM's viewport, the compositor's output
pass or FX-020's tail (tone map, flash guard). Rejected: a viewport/letterbox inside each renderer
(five code paths, the flash guard would see bars as content); CMP-006's `LayerFit` (fits layer
content inside a picture, not a picture onto a screen; reused only for its vocabulary).

## OUT-004-D2: Geometry

Units: slot points (square for the purposes of layout). Display physical width = W·p (p = PAR, pixel
width / pixel height, UIKit's definition), height H. Source aspect a (width / height, physical):
display shape → a = W·p/H; device shape → device slot width / height.

- Fit: if a ≥ W·p/H → (Pw, Ph) = (W·p, W·p/a) else (H·a, H). Fill: the opposite choice.
- The view's bounds = (Pw, Ph), transform scaleX = 1/p, centre = slot centre. On-screen frame
  = (Pw/p, Ph). A circle of radius r in bounds units is r/p pixels wide × r tall, i.e. r × r physically.
- Stretch: bounds = slot, identity (no PAR correction).

Invalid inputs (non-finite, ≤ 0 sizes) give identity; PAR non-finite or outside 0.5…2 reads 1.

## OUT-004-D3: Pixel aspect source

`UIScreenMode.pixelAspectRatio` (public, iOS 2+) of `window.windowScene.screen.currentMode`, read at
each layout of the external slot; `UIScreen.modeDidChangeNotification` triggers a re-layout. The
DEBUG fake display sits on the device's own screen (PAR 1); the manual override exercises other PARs.

## OUT-004-D4: Recording

OUT-002 holds the placement while recording; changing the view's bounds would change the drawable
size and stop the recording (REC-003-R11). The coordinator keeps the applied correction while held
and pushes the new one when the hold ends.

## OUT-004-D5: Verification without a non-square display

Pure geometry tests (package) are the acceptance. An app unit test draws a circle grid in a plain
`UIView` placed through the real slot and renders the slot's layer tree to a bitmap, measuring the
circle extents; PAR comes from the override. Physical composite/analog adapters are `{device}`.
