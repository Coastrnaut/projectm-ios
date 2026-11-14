# Data Model: SCN-012 Scene Validation

All types are in memory; nothing is stored.

## SceneRepairReport (SceneFormat)

| Field | Meaning |
|---|---|
| `entries: [Entry]` | In group order, then source order (refusal; decode warnings; validation order). |
| `canOpenAsIs` | No entry is `cannotOpen` or `needsRepair`. |
| `canOpenWithRepairs` | No entry is `cannotOpen` and `repairActions` holds an action that changes something. |
| `cannotOpen` | Some entry is `cannotOpen`. |
| `needsReview` | Some entry is `problem`, `needsRepair` or `cannotOpen` (the app shows the sheet). |
| `repairActions: [SceneRepairAction]` | Union of entries' actions, in canonical order. |
| `groups` | Groups that have entries, in `Group.allCases` order. |

## Entry

`group`, `severity`, `item` (plain words: "Layer 2 (photo)", "Photo \"photo\"", "Mapping 1
(audio.rms → visual.x)", "Scene"), `problem` (the SCN-001 message), `ifOpened` (what happens if opened
anyway), `actions`, `code` (issue code raw value or `refusal.<kind>`), `path`.

## Group (ordered)

`damagedFile`, `unsupportedVersion`, `missingMedia`, `invalidMappings`, `unknownContent`,
`valuesAdjusted`. Titles: "Damaged file", "Unsupported version", "Missing media", "Invalid
mappings", "Unknown content kept", "Values adjusted".

## Severity (ordered)

`note` < `problem` < `needsRepair` < `cannotOpen`.

## SceneRepairAction (canonical order)

| Action | Title | Owns codes |
|---|---|---|
| `renameScene` | Name it "Untitled scene" | invalidName |
| `renumberLayers` | Renumber duplicate layers | duplicateInstance, instanceOutOfRange |
| `removeBrokenLayers` | Remove damaged layers | danglingAsset, assetTypeMismatch, invalidAssetKey, invalidStoreID, invalidTextAsset, invalidGraphAsset, unknownMaterial |
| `removeExtraLayers` | Remove extra layers | kindLimit |
| `dropInvalidValues` | Drop invalid values | invalidValueName, malformedParameterID |
| `dropInvalidModulation` | Remove invalid modulation generators | invalidModulation |
| `dropMissingMedia` | Open without the missing media | missingAsset |
| `repairGroups` | Fix layer groups | invalidGroup (CMP-011: drops bad child references, then groups still invalid; a warning shown as a problem under "Damaged file") |
| `dropInvalidMappings` | Drop invalid mappings | invalidBinding, duplicateBindingTarget, invalidExpression, orphanedBinding, orphanedConnection, rejectedConnection, retiredReference |
| `keepUnknownContent` | Keep unknown content | unknownLayerKind (changes nothing) |

Not repairable (`cannotOpen`): `invalidSceneID` and every `SceneDecodeError`.

## SceneRepairRequest (app)

`id`, `title` ("Cue 2 · Broken", "Last scene"), `report`, `document?`, `open(SceneDocument)`,
`cancel()`. States: pending → opened (repaired | as is) or cancelled; a newer request cancels the
pending one.
