# Contract: FX-020 Effect chain

## E1 Renderer

1. `Compositor.outputEffectOrder` (default `.standard`) is read per frame.
2. Fixed after it: the composite flash guard (FX-019; measures `cmp_display` of the shown frame) and the
   output pass (grade if not already applied, tone map, × gain). No value of the order can change this.
3. Color first is rendered as a separate grade pass only when Trails are active and the grade is not
   neutral; otherwise the output equals the pre-FX-020 output bit for bit.
4. Changing the order resets the Trails history.
5. `encodeOutput` (recording) and frame capture repeat the shown frame's grade block (neutral when the
   grade pass ran).

## E2 Scene document

```json
"effects": [
  {"kind": "fx.grade", "enabled": true,
   "parameters": {"temperature": 0.0, "lift": 0.0, "gamma": 1.6, "gain": 1.0, "saturation": 1.4, "hue": 0.0}},
  {"kind": "fx.trails", "enabled": true, "parameters": {"halfLife": 0.3}}
]
```

- Optional; absent → byte-identical documents and today's order. At most 16 entries (`tooMany`).
- `kind` string (required), `enabled` bool, `parameters` object; wrong types → `malformed`.
- Warnings (SCN-012): `unknownEffectKind` (unknown content, kept), `fixedEffectStage` (values adjusted:
  "Flash safety and tone map always run last"), `duplicateEffect` (values adjusted, ignored, kept),
  `valueClamped` for parameters out of range or not numbers.
- Saving keeps every non-live entry at its index and writes live values into known entries.

## E3 Presets

`settings.effectChain.presets` = canonical JSON `{"version": 1, "presets": [{"name": "…", "effects": [E2
entries]}]}`. ≤ 32 presets; names 1…60 characters; a repeated name (case-insensitive) replaces. Applying
a preset applies its entries exactly as opening a scene with that `effects` list.

## E4 App

- Order key `settings.effectChain.order` (`fx.trails,fx.grade`), Color switch `settings.colorGrade.enabled`.
- Applied to Camera, Photo, Video and Text compositors at creation and on change.
- Opening a scene: with a list → order, flags and values applied through the settings (ACC-012 caps still
  apply); without → standard order, values untouched.
- Effect order screen: accessibility identifiers `effectChain.row.trails`, `effectChain.row.grade`,
  `effectChain.toggle.<kind>`, `effectChain.savePreset`, `effectChain.preset.<name>`; Settings row
  `settings.effectOrder` with value text "Trails → Color".
