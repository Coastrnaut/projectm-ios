# Quickstart: SCN-014 Scene Dependency Pack

1. Package: `swift test --package-path Packages/SceneArchive` (slides round trip, path audit, crafted packs).
2. App acceptance on the feature simulator: `ScenePackAcceptanceTests` (photo + 2 slides + logo + text →
   export → audit → wipe stores → import offline → equal scene, byte-identical media, cue; missing file;
   traversal; re-import dedup).
3. UI: `ScenePackUITests` with `-uitestScenePackFixture`: Scene Folders → Export Scene… → status →
   Import Scene… → preview → Import → the cue "Pack Scene copy" appears (< 30 s).
4. Manual (optional, any device): export a scene, Save to Files, erase the app's media in Settings, import
   the file with Airplane Mode on; the cue shows the same pictures.
