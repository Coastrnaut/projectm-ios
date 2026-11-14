# Contract: Shader parameter metadata (SHD-003)

## M1 Reading and validation
`ShaderMetadataReader.validate(json: String, document: String) throws(ShaderMetadataError) -> ValidatedShaderMetadata`
- Throws exactly one error, the first found in document order. `error.description` names the document,
  the path (`parameters[2]`, `parameters[2].cases[1]`) or parameter ID, and the key.
- Error cases: `malformedJSON`, `notAnObject`, `unknownKey`, `missingKey`, `keyNotAllowed`, `wrongType`,
  `unsupportedSchema`, `invalidID`, `invalidLabel`, `unknownKind`, `unknownUnit`, `nonFinite`, `notWhole`,
  `invertedRange`, `invalidStep`, `defaultOutOfRange`, `defaultOffStep`, `invalidColor`, `caseCount`,
  `duplicateCaseID`, `defaultNotACase`, `duplicateParameterID`, `parameterCount`, `slotMismatch`,
  `missingRequiredParameter`, `undeclaredSlotRead`, `slotTypeMismatch`.

## M2 Shader check
`ShaderSlotUsage.scan(source:function:) -> ShaderSlotUsage?` (nil when the function is absent);
`ValidatedShaderMetadata.check(against:) throws(ShaderMetadataError)`.

## M3 Registration
`ValidatedShaderMetadata.descriptors(idPrefix: "material.<variant>", group:)` → MOD-001 descriptors, one per
parameter in order (R5). `ProceduralMaterialCatalog.materials` are built from these.

## M4 Controls
`ShaderParameterControls.controls(for: ValidatedShaderMetadata, idPrefix:, values: [ParameterID: ParameterValue]) -> [ShaderParameterControl]`
— one per parameter, in order; invalid or missing values show the default.

## M5 App
Layer detail of a `material` layer: section "Material settings" (`materialSettings`), controls with identifier
`materialControl.<parameter ID>`, accessibility label = control label, value = UIX-003 spoken text; disabled
while the layer is read-only.
