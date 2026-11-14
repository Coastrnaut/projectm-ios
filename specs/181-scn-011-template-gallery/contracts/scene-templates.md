# Contract: Scene templates (SCN-011)

- **T1 Catalog**: `SceneTemplateCatalog.load(directory:)` reads `manifest.json`; a template whose scene file is missing, does not decode, or decodes with warnings is left out (`skipped` lists its ID); a bad manifest gives an empty catalog. Reads only.
- **T2 Copy**: `ShowStore.storeTemplateCopy(_:newID:name:)` writes `duplicated(newID:name:)` of the template document as canonical bytes under the new ID; refuses an invalid ID or name and an ID that already has a file (`sceneIDTaken`); never writes the template's folder.
- **T3 Add**: `ShowCoordinator.addTemplate(_:)` refuses (nothing written) when `cues + scenes > 256`; otherwise stores every copy, appends one cue per scene (label, transition), tags each copy with the template's tags, saves once, reports `sceneFilesChanged`, announces "Added <name> from templates." on the library lane, never applies a scene or moves the position. Returns the new cues.
- **T4 Licences**: every asset key of every template scene appears exactly once in that scene's `assets` records with licence `MIT`; no layer kind outside the three native kinds.
- **T5 UI**: Settings → Show → "Add from Template…" (`showAddFromTemplate`) opens the gallery (`sceneTemplateGallery`); each row `sceneTemplate.<id>` reads "<name>, <summary>" with hint "Adds its cues to the show"; choosing one adds it and closes the sheet.
