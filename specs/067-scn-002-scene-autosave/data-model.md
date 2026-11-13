# Data Model: SCN-002 Scene Autosave

## SceneInputs (app, Equatable, Sendable)

What the user can edit today; observed for edits, captured into a document.

| Field | Source | Scene |
|---|---|---|
| `visual` | `AppSettings.visual` (Camera → the visual chosen before it) | layer stack (D1) |
| `bars` | `circularSpectrumBars` | `visual.circularSpectrum.barCount` (enum "16"…"128") |
| `orientation` | `linearSpectrumOrientation` | `visual.linearSpectrum.orientation` (enum) |
| `spacing` | `linearSpectrumSpacing` | `visual.linearSpectrum.spacing` (continuous) |
| `glowEnabled`, `glowIntensity`, `glowRadius`, `glowThreshold` | AppSettings | `effect.bloom.*` |
| `text` | `TextOverlayCoordinator.spec` (stored JSON) | asset `text` (embedded), layer `text` |
| `photoID`, `videoID` | `PhotoCoordinator.photo`, `VideoCoordinator.video` | assets `photo`, `video` |

Bindings are read separately (`NativeSpectrumHost.bindings`, nil without the host); not an edit trigger.

## SceneAutosaveCarry (app)

From the restored document (or empty): `id`, `name`, `extra`, `layers` (all, with index), `assets`
(minus `photo`, `video`, `text`), `parameters` (minus the seven app-held IDs), `bindings`, `expressions`,
`modulation`, `preserved` (from `liveState`).

## SceneAutosaveDebouncer (app)

`quiet` (1 s), `maximumLatency` (5 s), `firstPending`, `lastEdit` (seconds on the injected clock).
`edit(at:)`; `deadline = min(lastEdit + quiet, firstPending + maximumLatency)`; `isDue(at:)`;
`reset()` after a commit is captured. States: idle → pending (edit) → idle (commit).

## SceneAutosaveStore (app)

`directory` (`Application Support/Scenes`), `main` (`current.scene`), `backup` (`current.scene.bak`),
`temporary` (`current.scene.tmp`); `mainIsGood` (Bool); test `fault` hook per `Step`
(`writeTemporary`, `flushTemporary`, `removeBackup`, `linkBackup`, `replaceMain`, `flushFolder`).
`load(registry:assets:) -> SceneAutosaveLoad` (`document`, `result` (`SceneLoadResult`), `source`
`main|backup|none`, `events`); `save(_ bytes:) throws`; `removeAll()`.

## SceneAutosaveEvent (app)

`mainUnreadable(String)`, `backupUnreadable(String)`, `restoredFromBackup`, `nothingRestored`,
`setAsideNewer`, `writeFailed(String)`, `droppedLayers(Int)`, `renumberedLayer(UInt64)`.

## Revisions

`editRevision` (+1 per edit), `committedRevision` (newest revision written), `pending =
editRevision > committedRevision`.
