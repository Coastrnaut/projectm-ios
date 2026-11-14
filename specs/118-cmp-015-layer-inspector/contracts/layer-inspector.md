# Contract: Layer Inspector (CMP-015)

## L1 Screen and identifiers

- Settings row `layersLink` ("Layers", value "N layers") opens `LayerInspectorView` (title "Layers").
- List rows top first: `layerRow.<instance>` (label "<title>", value "Layer <position> of <count>,
  editable|read only"); buttons `layerSolo.<instance>`, `layerMute.<instance>` (drawn layers only;
  value "On"/"Off").
- The detail (title = the layer's name) shows read-outs with identifiers `layerValue.<parameter>`
  (label = title, value = the shown value, e.g. "80%", "Screen", "0.25", "15°"), controls
  `layerControl.<parameter>`, help buttons `layerHelp.<parameter>`, and Reset Layer
  (`layerReset`). Undo/Redo (`sceneUndo`, `sceneRedo`) are in both navigation bars.

## L2 Values

- Opacity 0…1 shown as percent; blend: the six mode titles or "Other (<name>)"; position X/Y −1…1
  (2 decimals); scale 0.1…4 (2 decimals, "×"); rotation −180…180 (degrees, whole); fit: "Default",
  "Fill", "Fit", "Stretch", "Pixel accurate" or "Other (<name>)"; fit anchor 0…1; mask: "None",
  "Ellipse", "Rectangle", "Polygon (N points)" or "Other (<name>)"; mask size 0.1…2, corner radius
  0…0.5, feather 0…0.5, invert On/Off.

## L3 Editing

- Every control writes the kind's `SceneComposite` in `LayerInspectorCoordinator.composites`; the
  value is clamped by the composite types' own rules.
- Slider history key `layer.<kind>.<parameter>`; a drag ends coalescing on release; pickers and
  toggles record a step each; Reset Layer is one step.
- The shown host applies the new settings before the next frame; undo restores the stored value
  exactly (byte-equal document, pixel-equal frame).

## L4 Solo and mute

- Transient per kind; applied to the shown host as `LayerSoloMute`; cleared on a visual change; never
  in `SceneInputs`, the document or the history; announced (kind `.layer`): "<title> soloed",
  "<title> not soloed", "<title> muted", "<title> unmuted".

## L5 DEBUG seed

- `-uitestLayerInspectorSeed` (with `-uitestSeedPhoto solid`): Photo visual; photo opacity 80 %, fit
  "Fit"; spectrum opacity 60 %, blend Screen, position X 0.25; a carried `material.plasma` layer on
  top at 50 %, blend Add. The history starts from this scene.
