# Contract: Material variants (SHD-004)

**V1 Validation.** `ShaderMetadataReader.validate` accepts an optional `variants` list (data-model.md) and
throws: `variantCount`, `duplicateVariantID`, `defaultVariantMismatch` (first ID ≠ `variant`),
`variantPrefix` (ID does not start with `variant`), `unknownGPUFamily`, `defaultVariantRequirement`, plus the
existing `unknownKey`/`missingKey`/`wrongType`/`invalidID`/`invalidLabel` for entries.

**V2 Catalog.** `MaterialDefinition.variants` lists the validated variants; `fragmentFunction(for:)` is
`mat_<id>`; every variant passes `check(source:function:)` (unit test and `prepare`).

**V3 Layer.** `ProceduralMaterialLayer(definition, variant:, capabilities:)`. `prepare` builds the default and
every supported variant's pipeline (once; kept across size changes). `select(variant:)` (nil or the default ID
= default, stored as nil) changes only the selection and resolution — never parameters, motion or pipelines.
`render` draws the resolved pipeline. Resolution per research SHD-004-D4. Call `select` from the thread that
drives `render`, between frames.

**V4 Scene.** `materialVariant` written only when non-nil; decode → live state → capture → encode is
byte-equal; `unknownMaterialVariant` warning for an unlisted name.

**V5 Inspector.** For a material with ≥ 2 variants, the Material settings section starts with a picker
labelled "Variant", identifier `materialVariant`, options = variant labels in order, value = the stored
variant (default when nil or unknown), disabled while material layers are not drawn; a note
`materialVariantNote` when the stored variant is unsupported on this device.
