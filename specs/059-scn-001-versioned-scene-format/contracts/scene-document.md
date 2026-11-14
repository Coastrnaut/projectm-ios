# Contract: Scene document, format version 1

Module `SceneFormat` (`Packages/SceneFormat`). Requirements SCN-001-R1 to R14; decisions
SCN-001-D1 to D9 (research.md).

## C1 — Document (JSON, UTF-8)

```json
{
  "assets": { "<assetKey>": <asset>, ... },
  "bindings": [ <binding>, ... ],
  "format": "projectm-ios.scene",
  "id": "<uppercase UUID>",
  "layers": [ <layer>, ... ],                 // bottom first
  "modulation": { "connections": [...], "generators": [...] },   // optional; omitted when both empty
  "name": "<1…120 characters>",
  "parameters": { "<ParameterID>": <value>, ... },
  "version": 1
}
```

Required: `format`, `version`, `id`, `name`. `layers`, `parameters`, `bindings`, `assets` read as
empty when absent and are always written. Unknown top-level keys are kept (C6).

### Layer

```json
{ "composite": { "blend": "normal", "opacity": 1.0,
                 "transform": { "anchor": {"x":0.5,"y":0.5}, "rotation": 0.0,
                                "scale": {"x":1.0,"y":1.0}, "translation": {"x":0.0,"y":0.0},
                                "version": 1 } },
  "content": { ... },              // per kind, see table
  "instance": 1,                   // 1 … 9007199254740991
  "kind": "spectrum.circular",
  "values": { "<name>": <number>, ... } }
```

| `kind` | `content` | Live `LayerKind` |
|---|---|---|
| `camera` | none | `.camera` (max 1) |
| `spectrum.circular` | none | `.circularSpectrum` |
| `spectrum.linear` | none | `.linearSpectrum` |
| `photo` | `{"asset": "<key>"}` (a `photo` asset) | `.photo` (max 1) |
| `video` | `{"asset": "<key>"}` (a `video` asset) | `.video` (max 1) |
| `text` | `{"asset": "<key>"}` (a `text` asset) | `.text` (max 1) |
| `material` | `{"material": "material.<name>"}` (SHD-001 catalog) | `.material` |
| `generator.graph` | `{"asset": "<key>"}` (a `generatorGraph` asset) | `.generatorGraph` |
| anything else | kept verbatim (with every other key of the layer) | not in the live stack |

`composite` reads defaults when absent (opacity 1, blend `normal`, identity transform) and is
always written. `transform` is CMP-005's saved form (`version` 1). Opacity and transform components
outside their ranges are clamped on decode with a `valueClamped` warning. `blend`: any string;
`normal`, `add`, `screen`, `multiply`, `overlay` and `difference` are drawn (CMP-004, ADR-0037), others
give `unsupportedBlendMode` and are kept. `values`: the layer's own
numbers (`LayerDescriptor.parameters`), names 1…64 UTF-8 bytes without control characters.

### Parameter value (MOD-001 tagged form)

`{"kind":"continuous","value":0.25}`, `{"kind":"integer","value":64}`,
`{"kind":"boolean","value":true}`, `{"kind":"enum","value":"vertical"}`,
`{"kind":"color","value":[1.0,0.5,0.0,1.0]}`. An unknown `kind` is malformed (C4).

### Binding

```json
{ "envelope": {"attack": 0.05, "release": 0.3},
  "expression": "band(2) * 2",         // optional (SHD-009 source text)
  "input": {"maximum": 1.0, "minimum": 0.0},
  "mix": "replace",                    // replace | add | multiply
  "output": {"end": 0.5, "start": 0.0},
  "source": "audio.band.2",            // MOD-002 source ID
  "target": "visual.circularSpectrum.gap" }
```

`input` defaults to 0…1, `envelope` to 0/0, `mix` to `replace`; `source`, `target` and `output`
are required. Unknown binding keys are kept.

### Modulation

`generators`: `[{"id": "lfo.one", "inputs": ["rate"], "name": "LFO One"}]`;
`connections`: `[{"input": "value", "source": {"id": "lfo.one", "kind": "generator"},
"target": {"id": "visual.circularSpectrum.gap", "kind": "parameter"}}]` with node `kind` one of
`audio`, `parameter`, `generator`. `input` defaults to `value`.

### Asset

`{"storeID": "<UUID>", "type": "photo"}`, `{"storeID": "<UUID>", "type": "video"}`,
`{"spec": {<MED-009 TextOverlaySpec JSON, version 1>}, "type": "text"}`,
`{"document": {<SHD-002 graph document>}, "type": "generatorGraph"}`; any other `type` is kept
verbatim. Asset keys: a lowercase ASCII letter, then ASCII letters and digits, at most 64 bytes.

## C2 — Canonical encoding

UTF-8, no white space; object keys sorted by their UTF-8 bytes; strings escape only `"` `\` and
U+0000…U+001F (`\b \f \n \r \t`, others `\u00XX` lower-case hex); doubles as Swift
`Double.description` (`0.1`, `1.0`, `1e-07`, `-0.0`); integers in decimal; preserved unknown
numbers in their written text. `encode(decode(b)) == b` for every canonical `b`.

## C3 — Semantic equality (`SceneDocument ==`)

Equal scene ID, name, layers in order (instance, kind and content, values, opacity, blend,
transform), parameter values, bindings in order, generators and connections in order, assets and
every preserved unknown field; doubles compared by bit pattern; map key order and white space never
matter; preserved unknown numbers compared by their written text.

## C4 — Decode refusals (`SceneDecodeError`, `message`)

Checked in this order; the first failure is thrown and nothing is returned.

| Case | Message |
|---|---|
| `empty` | `The file is empty.` |
| `tooLarge(bytes:limit:)` | `The scene is <bytes> bytes; scenes are at most 1048576 bytes.` |
| `notJSON(offset:reason:)` | `The scene is not valid JSON at byte <offset>: <reason>.` |
| `nestingTooDeep(limit:)` | `The scene nests deeper than 32 levels.` |
| `duplicateKey(path:key:)` | `<path> has the key "<key>" twice.` |
| `notAScene` | `The file is not a projectM-iOS scene.` |
| `newerVersion(_:)` | `This scene was saved by a newer version of the app (format version <n>); this version reads format version 1.` |
| `invalidVersion(_:)` | `The scene's format version must be a whole number from 1; found <text>.` |
| `tooMany(what:count:limit:)` | `The scene has <count> <what>; at most <limit> are allowed.` |
| `malformed(path:reason:)` | `<path>: <reason>.` |

Paths: `$`, `$.layers[2].composite.opacity`, `$.parameters["visual.circularSpectrum.gap"]`.
`what` is one of `layers`, `bindings`, `parameter values`, `assets`, `values in layer <i>`,
`modulation generators`, `modulation connections`.

## C5 — Validation issues (`SceneIssue`: severity, code, path, message)

`decode` returns decode-time warnings; `validate(registry:assets:)` returns every issue in document
order (layers, assets, parameters, bindings, modulation). Errors block `liveState`; warnings do not.

| Code | Severity | Message |
|---|---|---|
| `invalidSceneID` | error | `The scene ID "<id>" is not an uppercase UUID.` |
| `invalidName` | error | `The scene name must be 1…120 characters without control characters.` |
| `instanceOutOfRange` | error | `Layer <i> has instance ID <id>; IDs are 1…9007199254740991.` |
| `duplicateInstance` | error | `Layer <i> uses instance ID <id>, already used by layer <j>.` |
| `kindLimit` | error | `Layer <i> is "<kind>" layer number <n>; a scene holds at most <max>.` |
| `invalidValueName` | error | `Layer <i> has a value named "<name>"; names are 1…64 bytes without control characters.` |
| `unknownLayerKind` | warning | `Layer <i> has the unknown kind "<kind>"; it is kept but not shown.` |
| `unsupportedBlendMode` | warning | `Layer <i> uses the blend mode "<mode>", which this version draws as normal.` |
| `valueClamped` | warning | `<path>: <value> is outside <range>; read as <clamped>.` |
| `droppedField` | warning | `<path> has the unknown field "<key>"; it was dropped.` |
| `unknownMaterial` | error | `Layer <i> uses the unknown material "<id>".` |
| `danglingAsset` | error | `Layer <i> refers to the asset "<key>", which the scene does not define.` |
| `assetTypeMismatch` | error | `Layer <i> (<kind>) refers to the asset "<key>", which is a <type> asset.` |
| `invalidAssetKey` | error | `The asset key "<key>" must start with a lowercase ASCII letter and hold only ASCII letters and digits (at most 64).` |
| `invalidStoreID` | error | `Asset "<key>" has the store ID "<id>"; store IDs are uppercase UUIDs, never paths.` |
| `invalidTextAsset` | error | `Text asset "<key>" is damaged.` or `Text asset "<key>" uses text format version <v>, which this version cannot read.` |
| `invalidGraphAsset` | error | `Generator graph asset "<key>" is refused: <SHD-011 importer message>` |
| `unknownAssetType` | warning | `Asset "<key>" has the unknown type "<type>"; it is kept but not used.` |
| `unusedAsset` | warning | `Asset "<key>" is not used by any layer; it is kept.` |
| `missingAsset` | warning | `Asset "<key>" (<type> <id>) is not on this device; its layer draws nothing until it is restored.` |
| `malformedParameterID` | error | `The parameter ID "<id>" is ill-formed: <MOD-001 syntax problem>.` |
| `orphanedParameter` | warning | `"<id>" is not a parameter of this version; its value is kept but not applied.` |
| `rejectedParameter` | warning | `<MOD-001 ParameterStoreError message>; the current value is kept.` |
| `parameterClamped` | warning | `"<id>" value <value> is outside its range; it is applied as <stored>.` |
| `invalidBinding` | error | `Binding <i>: <MOD-002 AudioFeatureBindingError message>.` |
| `duplicateBindingTarget` | error | `Binding <i> targets "<id>", already bound by binding <j>.` |
| `invalidExpression` | error | `Binding <i> expression: <SHD-009 ExpressionError description>.` |
| `invalidModulation` | error | `Modulation: <MOD-014 issue message>` (cycles name their path) |

`<value>` texts are Swift's `description` of the number; `<i>`, `<j>` are 0-based indexes.

## C6 — Live adapters

- `SceneDocument(capturing: SceneLiveState, id:, name:) throws(SceneCaptureError)`: every stack
  entry needs a content of its own kind (`missingContent`, `contentMismatch`).
- `document.liveState(registry:assets:) throws(SceneLoadError) -> SceneLiveState`: refuses with
  every error issue (`invalid([SceneIssue])`); otherwise rebuilds `LayerStack(restoring:)` (saved IDs
  and order; unknown kinds left out), contents by instance ID, the parameter snapshot (values as
  written, schema 1), MOD-002 bindings and expressions, the modulation graph and the assets.
- `LayerStack.init(restoring: [LayerStackEntry]) throws(LayerStackError)`: refuses
  `duplicateLayer(id)`, `stackFull`, `kindLimitReached`; the next added layer gets the largest
  restored ID + 1 (CMP-002 amendment).

## C7 — Safety

The module reads no files, opens no URLs, uses no networking, evaluates nothing from the document
(expressions are compiled only; graph documents only checked), and is pure Swift on Linux.
