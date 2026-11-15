# Contract: OUT-003 output resolution

## C1 — `ExternalOutputResolution.resolve` (PresentationLifecycle, pure)

`resolve(width:height:nativeScale:budget:) -> ResolvedExternalOutput` with the slot's size in
points. Guarantees (OUT-003-S1):

- `pixelWidth ≤ round(width·nativeScale)` and likewise for height (never upscaled);
- `max(pixelWidth, pixelHeight) ≤ budget.maxSide` and `pixelWidth·pixelHeight ≤ budget.maxPixels`;
- for 1080p / 720p, long side ≤ 1920 / 1280 and short side ≤ 1080 / 720;
- the shape is kept within one pixel; with nothing limiting, the result is native and `isNative`.

## C2 — `VisualSlotView` (app)

- External role: `resolution` and `pixelBudget` properties; `applyPlacement()` resolves with the
  slot's bounds and its own `traitCollection.displayScale`, then sets
  `traitOverrides.displayScale` on each held view (removed when the result is native) and asks it
  to lay out. Bounds, centre and transform come only from OUT-004's placement.
- Device role and `removeVisuals()`: remove the override.
- `resolvedOutput`: the last result (tests, probe).

## C3 — `ExternalDisplayCoordinator` (app)

- `resolution` (didSet pushes to every external slot inside the call, unless a recording holds
  the placement — then when the hold ends); `pixelBudget` set once at launch.
- `externalResolutionSummary`: `"mode=<mode> scale=<x.xx> drawable=<W>x<H> clamped=<yes|no>"`
  for the slot holding the visual (`drawable` is the resolved pixel size), nil when the visual is on the device.

## C4 — `ExternalOutputSetting` (app)

- `resolutionMode`, `resolutionPercent`; stored under the two keys; pushed to the coordinator.
- Settings › External Display: picker `externalResolutionPicker`, slider `externalResolutionPercent` (Custom only).
- DEBUG probe `externalResolution` on the fake display panel.
