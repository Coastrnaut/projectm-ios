# Data Model: SCN-001 Versioned Scene Format

Swift types in module `SceneFormat`; JSON form in [contracts/scene-document.md](contracts/scene-document.md).

| Type | Fields | Rules |
|---|---|---|
| `SceneDocument` | `id: String`, `name: String`, `layers: [SceneLayer]`, `parameters: [ParameterID: ParameterValue]`, `bindings: [SceneBinding]`, `modulation: SceneModulation`, `assets: [String: SceneAsset]`, `extra: [String: SceneJSON]` | Format `projectm-ios.scene`, version 1 (constants). Equatable = semantic equality (C3). |
| `SceneLayer` | `instance: UInt64`, `content: SceneLayerContent`, `values: [String: Double]`, `composite: SceneComposite`, `extra` | `kind` is derived from `content`. |
| `SceneLayerContent` | `camera`, `circularSpectrum`, `linearSpectrum`, `photo(asset:)`, `video(asset:)`, `text(asset:)`, `material(id:)`, `generatorGraph(asset:)`, `unknown(kind:)` | Unknown kinds keep all their other keys in the layer's `extra`. |
| `SceneComposite` | `opacity: Double`, `blendMode: String`, `transform: LayerTransform` | Opacity clamped to 0…1 on decode; transform per CMP-005. |
| `SceneBinding` | `source: AudioFeatureSource`, `target: ParameterID`, `mapping: LinearMapping`, `mix: ModulationMixMode`, `envelope: AudioFeatureEnvelope`, `expression: String?`, `extra` | Converts to and from `AudioFeatureBinding`. Order significant. |
| `SceneModulation` | `generators: [ModulationGenerator]`, `connections: [ModulationEdge]` | MOD-014 types; validated with the bindings' edges. |
| `SceneAsset` | `kind: SceneAssetKind`, `extra` | |
| `SceneAssetKind` | `photo(storeID:)`, `video(storeID:)`, `text(spec: SceneJSON)`, `generatorGraph(document: SceneJSON)`, `unknown(type:)` | Store IDs: uppercase UUID text. |
| `SceneJSON` | `null`, `bool`, `number(SceneNumber)`, `string`, `array`, `object([String: SceneJSON])` | Parsed with depth limit and duplicate-key refusal. |
| `SceneNumber` | `text: String` | Exact written text; `doubleValue`, `int64Value`. |
| `SceneIssue` | `severity`, `code`, `path`, `message` | C5. |
| `SceneDecodeError` | cases of C4 | `message`. |
| `SceneLiveState` | `stack: LayerStack`, `contents: [LayerInstanceID: SceneLayerContent]`, `parameters: ParameterSnapshot`, `bindings: [AudioFeatureBinding]`, `expressions: [ParameterID: String]`, `modulation: SceneModulation`, `assets: [String: SceneAsset]` | Live side of C6. |
| `SceneAssetAvailability` (protocol) | `contains(photo:)`, `contains(video:)` | The app's stores answer; tests use a fake. |

## Lifecycle

bytes → (size check) → parse (`SceneJSON`, depth, duplicates) → format/version → count limits →
typed decode (+ decode warnings) → `SceneDocument` → `validate(registry:assets:)` → issues →
`liveState` (refused on any error) → app stores. The reverse: live state → `SceneDocument(capturing:)`
→ `encoded()` canonical bytes.
