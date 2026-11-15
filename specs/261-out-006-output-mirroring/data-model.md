# Data Model: OUT-006 Output Mirroring Toggle

- **ExternalOutputMode** (enum, raw values stored): `sameScene` (default), `clean`. Unknown or missing → `sameScene`.
- **OutputLayerClass** (enum): `visual` (the chosen visual and its own layers), `sceneOverlay` (MED-010 logo), `interface` (controls, badges, HUD, guides, performance overlay, captions, notes).
- **OutputLayerRouting** (pure rule): device: visual, sceneOverlay, interface. External, Same scene: visual, sceneOverlay. External, Clean: visual. `routesSceneOverlays(target:mode:)` = includes(sceneOverlay).
- **Stored value**: `settings.externalDisplay.outputMode` (String), device-local: excluded from the library backup, erased with Settings (FILE-011 external display keys), removed by `-uitestResetNotice`, allowed by `run_device_tests.py`.
- **State transitions**: `routesSceneOverlays` changes on a mode change or a change of the effective target; each change sets `LogoCoordinator.outputSuppressed = !routes`, which pushes the effective placement to every live logo layer.
