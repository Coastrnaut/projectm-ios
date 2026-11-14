# Contract: palettes (UIX-011)

## P1 File
`Application Support/Palettes/palettes.json`, UTF-8 JSON, canonical (sorted keys):
```json
{"format":"projectm-ios.palettes","palettes":[{"colors":["#2EC4FF","#FF4FD8"],"id":"<UUID>","name":"Neon","style":"gradient"}],"version":1}
```
Read: wrong `format` → not a palette file; `version` > 1 → newer (the store keeps the file and refuses edits);
entries with a bad ID, duplicate ID, empty/long name, unknown style, or fewer than 2 / more than 8 valid colours are
dropped and counted; more than 64 entries → the first 64. Built-ins are never written.

## P2 Scene links
Document field `palette` (string) = the scene's palette; layer field `palette` (string) = that layer's palette.
The app writes the scene's choice on the document and on its spectrum layers; absent = no link. No version change.

## P3 Resolution
`layer.palette ?? document.palette ?? builtin.spectrum`. A link to an unknown ID draws `builtin.spectrum` and is
reported `isMissing`; the link is never removed by reading. ACC-003's switch, when on, draws `builtin.colorBlindSafe`.

## P4 Rendering
Built-in IDs draw the VIS-001 cases exactly. A user palette draws `VisualPalette.custom`: gradient = linear-light
interpolation between evenly spaced stops; swatches = colour `min(floor(t·n), n−1)` for position t in 0…1.

## P5 Backup (FILE-005)
Record `palettes/palettes.json` (written when there is at least one user palette); records digest key `palettes`.
Plan entries `palette/<id>` in section `palettes`: new → add; identical → keep; clash → Keep both (copy under a derived
ID and "<name> copy"), Replace, Skip; a copy beyond 64 falls back to keep. Erase: folder `Palettes` with "Scenes and show".
Storage: `Palettes` under Scenes.
