# Data Model: PRE-007 Preset collections

## PresetCollection

| Field | Type | Rules |
|---|---|---|
| `id` | String | Opaque, permanent, unique among collections, non-empty. A UUID string when created by the app. Never shown. |
| `name` | String | 1-60 user-perceived characters after trimming; line breaks replaced by spaces; unique among collections ignoring case and diacritics (enforced on create and rename). |
| `presetIDs` (JSON `presets`) | [String] | Ordered by the user; each id at most once; at most 1,000 (enforced on add). Ids are `IndexedPreset.id` values and may name presets that are locked or absent from the current index. |

## PresetCollectionsFile (the saved document)

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | Int | 1 today. Greater → not interpreted. Smaller → migrated step by step. |
| `collections` | [PresetCollection] | Ordered by the user; at most 100 (enforced on create). |

Location: `<Application Support>/PresetCollections/collections.json`. Sibling files the store may
create: `collections.unreadable.json` (a set-aside unreadable document, at most one) and
`collections.v<n>.backup.json` (the original during a migration; removed after the migrated
document was saved). Maximum document size read: 16 MB.

## Store state

| State | When | Reads | Changes |
|---|---|---|---|
| available | no file, a current file, a migrated file, or after an unreadable file was set aside | the list | allowed |
| newerFormat(version) | the file's `schemaVersion` is greater than the app's | empty list | every change throws `newerFormat`; the file is never written |

`loadNotice`: `none` or `unreadableSetAside` (set once by the load that set a file aside).

## Operations and invariants

| Operation | Result | Refusals |
|---|---|---|
| create(name) | new empty collection appended | `emptyName`, `nameTooLong`, `duplicateName`, `tooManyCollections` |
| rename(id, name) | name changed; id, contents, position unchanged | `unknownCollection`, name errors (its own name is accepted) |
| delete(id) | that collection removed; nothing else changes | `unknownCollection` |
| add(presetID, id) | appended; returns false and changes nothing when already present | `unknownCollection`, `collectionFull` |
| remove(presetIDs, id) | those entries removed; order of the rest unchanged | `unknownCollection` |
| reorderPresets(id, visibleOrder) | visible entries take `visibleOrder`; hidden entries keep their slots | `unknownCollection`, `invalidOrder` |
| reorderCollections(ids) | the list takes that order | `invalidOrder` unless a permutation of all ids |

Every operation: `newerFormat` when unavailable; `saveFailed` when the write fails, with memory
and disk unchanged.

## Scope

`PresetScope.collection(id)`, stored as `collection:<id>` in `settings.presetScope`.

Members = the collection's `presetIDs`, in order → presets found in the index → not locked for the
current entitlement → not excluded this session.

Listing (what the collection screen shows) = `presetIDs` in order → presets found in the index
(locked ones included and marked).

## Relationships

- Collection → presets: by id only; many-to-many; no ownership. Deleting a collection deletes
  references, never presets.
- Favorites: independent set in UserDefaults; no shared state.
- Entitlement: read-only input (`unlocked`) to membership and to the row's lock mark.
