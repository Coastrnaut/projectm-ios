# Contract: Scene Autosave (SCN-002)

## A1 Files

`Library/Application Support/Scenes/`: `current.scene` (main), `current.scene.bak` (backup, the
previous committed scene), `current.scene.tmp` (only during a save), `current.scene.newer` (a newer-version file set aside once,
never written or read). Contents: SCN-001 canonical bytes
(`SceneDocument.encoded()`), format `projectm-ios.scene`, version 1.

## A2 Save sequence (each step may fail; failure throws, removes the temporary file, keeps the rest)

1. `writeTemporary`: create/truncate `current.scene.tmp` (mode 0600), write all bytes.
2. `flushTemporary`: `fcntl(F_FULLFSYNC)`, `fsync` if refused; close.
3. `removeBackup`: `unlink(current.scene.bak)` (absent is fine) — only when the main file is known good.
4. `linkBackup`: `link(current.scene, current.scene.bak)` — only when the main file is known good and
   exists.
5. `replaceMain`: `rename(current.scene.tmp, current.scene)`.
6. `flushFolder`: `fsync` of the folder (failure logged, the commit stands).

Invariant: after the first commit, at least one of main and backup is a complete committed scene at
every step.

## A3 Load

Remove `current.scene.tmp`; read main (≤ 1 MiB + 1 byte), `SceneDocument.decode`, `liveState(registry:
VisualParameterCatalog registry + material catalog, assets: stored photo/video)`; on any refusal try the
backup; else nothing. A `newerVersion` refusal moves that file to `current.scene.newer` (unless it
exists). Events per D5. Loading never throws and never presents UI.

## A4 Triggers

| Trigger | Commit |
|---|---|
| Parameter, text, photo or video edit | debounced: 1 s quiet, 5 s maximum latency |
| Visual choice changes | at once |
| Settings closes | at once (if pending) |
| `didEnterBackground` | at once, inside a background task |
| `willTerminate` | at once, synchronous |
| Restore at launch | none (not an edit) |

## A5 Restore (launch, before UI-test seeds)

Parameters: scratch `ParameterStore.restore` of the document's values → the seven app-held IDs written to
AppSettings (each setter's own range rules apply). Text: the `text` asset (if any) →
`TextOverlaySpec.decodeStored` → `TextOverlayCoordinator.spec`. Bindings: kept and bound to the native
spectrum when it is created. Photo/video: never changed (warnings only). Visual choice: never changed.

## A6 Probe (DEBUG, `-uitestDiagnostics`)

Accessibility identifier `sceneAutosave`, value
`restored=<main|backup|none> committed=<n> pending=<0|1> events=<n>`. DEBUG launch arguments
`-uitestSceneAutosaveQuiet <seconds>`, `-uitestSceneAutosaveMaxLatency <seconds>`. `-uitestResetNotice`
removes the folder.
