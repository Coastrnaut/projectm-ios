# Contract: Show document and cue stepping (SHOW-001)

## S1. File `show.json`, version 1

```json
{
  "cues" : [
    { "id" : "8B0C…", "label" : "Intro", "scene" : "2F1A…" }
  ],
  "format" : "projectm-ios.show",
  "id" : "D3E4…",
  "name" : "Show",
  "position" : "8B0C…",
  "version" : 1
}
```

- Keys sorted; UTF-8; `position` is `null` for Standby. UUIDs are canonical uppercase text.
- Unknown keys are ignored on read and not written back (the show is a closed structure in v1; a
  later version that adds fields raises `version`).
- Encoding the same list twice gives the same bytes; decode → encode of a written file is
  byte-identical.

## S2. Scene files

`Scenes/<sceneID>.scene.json` holds SCN-001 canonical bytes (`SceneDocument.encoded()`), whose `id`
equals `<sceneID>`. A file whose document `id` differs from its name is treated as missing.
Scenes are written before the show file that refers to them; after a save, scene files no cue refers
to are deleted.

## S3. Stepping

| From | next | previous |
|---|---|---|
| empty show | `.empty`, no change | `.empty`, no change |
| Standby | cue 1 (`.moved`) | `.atStart`, no change |
| cue n (1 < n < N) | cue n+1 | cue n−1 |
| cue 1 | cue 2 (or `.atEnd` if N = 1) | `.atStart` |
| cue N | `.atEnd` | cue N−1 |

`go(to:)` any existing cue → `.moved` (also the active one). Only `.moved` applies a scene.

## S4. Applying (app)

`.moved` → read the cue's scene file → SCN-001 decode + `liveState(registry:assets:)` → look →
`AppSettings` + text → `visualSettingsChanged()`, `glowSettingsChanged()`. Never: start/stop the audio
source, start the camera, change the blackout. Failure (missing/invalid) → position stays moved,
output unchanged, notice + VoiceOver announcement.

## S5. Load

Refusals (contract table in data-model.md "Validation") rename the file to
`show.damaged-<n>.json` and start an empty show; the editor shows "The saved show could not be read
and was set aside." once.
