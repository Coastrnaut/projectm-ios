# Data Model: PRE-003 Preset Tags

## PresetTagMap (stored)

| Field | Type | Rules |
|---|---|---|
| `tags` | preset ID → [String] | ID non-empty; each list 1-16 tags, sorted by (fold, text), no folded duplicates; ≤ 256 distinct folded tags overall; ≤ 20,000 entries; a preset without tags has no entry |

Tag: trimmed, 1-40 characters, no line breaks or control characters. Identity: fold (case, accents,
width; `nil` locale). Adding a tag whose fold already exists anywhere adopts that spelling.

## tags.json (version 1)

```json
{ "schemaVersion": 1, "tags": { "included/Geiss - Spiral.milk": ["Calm", "Slow"] } }
```

Sorted keys, no escaped slashes (equal maps → equal bytes). Bounds: 4 MiB, depth 4, strings ≤ 4 KiB,
≤ 20,000 elements per list or object, no duplicate keys.

## PresetTagIndex (memory)

- `idsByTag`: folded tag → Set<preset ID> (listed IDs only)
- `spelling`: folded tag → display spelling
- `vocabulary`: display spellings sorted by (fold, text)

## PresetTagStore states

`available` | `newerFormat(version)`; `loadNotice`: `none` | `unreadableSetAside` | `repaired(dropped)`.

## Backup record

`collections/tags.json` (the same document). Restore keys `tags/<preset ID>` in section `tags`.
