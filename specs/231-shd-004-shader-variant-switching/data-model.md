# Data Model: SHD-004 Shader Variant Switching

## Metadata document: `variants` (optional, SHD-004-R1)

| Key | Type | Required | Rule |
|---|---|---|---|
| `variants` | array of objects | no | 2–4 entries; absent = one implicit `{id: <variant>, label: "Standard"}` |
| `variants[i].id` | string | yes | well-formed ID, unique, starts with the document's `variant`; `variants[0].id` = `variant` |
| `variants[i].label` | string | yes | 1–64 characters, not only white space |
| `variants[i].requires` | string | no | `apple7`, `apple8` or `apple9`; not allowed on `variants[0]` |

## Types

- `ShaderGPUFamily` (ShaderParameterMetadata): `apple7`, `apple8`, `apple9`; raw value = metadata name; `displayName` "Apple GPU family 9".
- `ShaderVariantSpec`: `id`, `label`, `requires: ShaderGPUFamily?`. `ValidatedShaderMetadata.variants: [ShaderVariantSpec]` (first = default).
- `MaterialGPUCapabilities` (ProceduralMaterials): `families: Set<ShaderGPUFamily>`; `supports(_:)`; `.all`, `.none`; `init(device:)` on Metal.
- `MaterialVariantNotice`: `unknownVariant(String)`, `unsupported(variant: String, requires: ShaderGPUFamily)`, `pipelineUnavailable(String)`; `message`.
- `MaterialVariantResolution`: `drawn: String`, `notice: MaterialVariantNotice?`.
- `ProceduralMaterialLayer`: `selectedVariant: String?` (nil = default), `select(variant:)`, `resolution`, `capabilities`.

## Scene (SHD-004-R6)

- `SceneLayer.materialVariant: String?` — layer JSON key `materialVariant`, decoded for `material` layers only;
  non-text → dropped with `droppedField`.
- `SceneLiveState.materialVariants: [LayerInstanceID: String]` — filled by `liveState`, written back by capture.
- `SceneIssue.Code.unknownMaterialVariant` — warning, unknown content, no repair action, path `$.layers[i].materialVariant`.
