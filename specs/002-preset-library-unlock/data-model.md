# Data Model: Full Preset Library Unlock (feature 002)

## IndexedPreset (one record per unique preset; `PresetIndex.json`)

| Field | Type | Rule |
|-------|------|------|
| `id` | string | `<source>/<path in source>`; unique; Included ids unchanged from 1.0 (FR-104) |
| `name` | string | Display name: file name without `.milk`, author prefix removed when it matches `Author - Title` |
| `author` | string | Text before the first ` - ` in the file name; `Unknown` if none |
| `source` | string | `included`, `cream-of-the-crop`, `projectm-classic`, `milkdrop-original`, `en-d` |
| `folder` | [string] | Path components inside the source, without the file name (cream: [category, subcategory]; classic: [collection]; en-d: [episode]; original: []) |
| `path` | string | Bundle-relative path of the file (`Presets/<file>` or `PresetPacks/<pack>/<path>`) |
| `hash` | string | Git blob hash (40 hex) of the file content |

Validation: ids and hashes unique; every `path` exists in the bundle; `source` is one of the five
values; records sorted by `source` priority, then `folder`, then `name` (localized standard
compare at run time, FR-115).

## PresetPack (`PresetPacks.json`)

| Field | Type | Rule |
|-------|------|------|
| `id` | string | One of the four pack ids, or `included`, or `milkdrop-texture-pack` |
| `title` | string | Shown in the browser and Licenses |
| `sourceURL` | string | The upstream repository |
| `commit` | string | 40-hex pinned commit (must equal the submodule's) |
| `license` | string | The pack's license statement, or "No license file; distributed under the projectM team's basis (ADR-0007)" |
| `presetCount` | int | Unique presets after de-duplication and exclusions |
| `authors` | [string] | Sorted, unique |
| `locked` | bool | true for the four packs, false for Included and textures |

## Blocklist (`PresetBlocklist.json`)

`{ "hashes": [ { "hash": "<40 hex>", "reason": "author request <date>" } ] }` — the index skips
these in every source.

## Library (in memory, `PresetLibrary`)

Built once at launch from the index and packs, off the main thread:
- `presets`: all records, plus a folded search key per preset (lowercased, diacritics removed,
  `name + " " + author`).
- `tree`: source → folder → presets, with counts per node (FR-111, FR-112).
- `isUnlocked`: from the store (not stored).
- `excludedThisSession`: ids that failed to load (FR-118).
- `playable(preset)` = `!locked(source) || isUnlocked` and not excluded.

## PresetScope

| Kind | Payload | Persisted as (`settings.presetScope`) |
|------|---------|--------------------------------------|
| included | — | `included` |
| pack | pack id | `pack:<id>` |
| folder | pack id + folder path | `folder:<id>/<a>/<b>` |
| favorites | — | `favorites` |
| search | query | `all` (never stores text; spec Clarifications) |
| all | — | `all` |

Members = presets in that set, filtered by `playable`, sorted alphabetically (FR-115).
Transitions: purchase or restore → `pack:cream-of-the-crop` (FR-119); refund → `included` (FR-109);
a stored scope that no longer resolves (pack removed, folder renamed) → `included` before purchase,
`all` after.

## Entitlement

`fullLibrary: Bool` from StoreKit 2: true if `Transaction.currentEntitlements` contains a verified,
unrevoked transaction for `org.projectmios.ProjectMiOS.fullLibrary`. Updated from
`Transaction.updates`. Never written by the app (FR-110).

## Persistence (FR-123)

Existing keys (`favorites`, `lastPresetID`, `settings.performanceOverlay`, `settings.reduceFlashing`,
`notice.photosensitivityAcknowledged`) plus `settings.presetScope`. Nothing else.
