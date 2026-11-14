# Contract: REC-013 Offline Export

## C1 Renderer (app, off the main actor)

`OfflineSceneRenderer.export(job:audio:folder:isCancelled:progress:) throws -> OfflineExportResult`

- Renders `frameCount(audio)` frames per D1; never reads a real clock; never touches the live host or settings.
- Returns the MP4 URL, the sidecar URL and the manifest. Frame count of the MP4 = manifest `frameCount` = checksum count.
- `isCancelled()` is read before each frame; when true the recorder is cancelled (no MP4 remains) and `OfflineExportError.cancelled` is thrown. The coordinator deletes the folder.
- Errors: `.noDevice`, `.audioTooShort`, `.render(String)`, `.writer(String)`, `.cancelled`.

## C2 Determinism

Same job (apart from the folder) and the same audio samples on the same GPU → equal `frameChecksums`. A changed seed with a particle visual, or changed audio, gives different lists.

## C3 Coordinator (main actor)

- `start()` refuses: `.unsupportedVisual` (projectM, Camera, Photo, Video, Text), `.invalidSeed`, `.busy`, `.noAudioFile` (File chosen but none picked).
- Phases per data-model; progress "Rendering frame N of M"; messages announced on the library lane: "Exported N frames", "Export cancelled", "Export failed", "Export stopped: the app left the screen.", "This audio file can't be read.", "The audio is too short.".
- `sceneLeftForeground()` while loading or rendering = stop. `done()` deletes the folder. Leftover folders are deleted at init.

## C4 UI identifiers

`offlineExportOpen` (row), `offlineExportSheet`, `offlineExportAudio` (picker), `offlineExportChooseFile`, `offlineExportSeed`, `offlineExportShape`, `offlineExportRate`, `offlineExportStart`, `offlineExportCancel`, `offlineExportProgress`, `offlineExportStatus`, `offlineExportSave`, `offlineExportShare`, `offlineExportPhotos`, `offlineExportDone`.
