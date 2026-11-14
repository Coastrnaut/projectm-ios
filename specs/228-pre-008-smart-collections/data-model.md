# Data Model: PRE-008 Smart Collections

## PresetSmartCollection
| Field | Type | Rules |
|---|---|---|
| id | String | `smart-<UUID>`, permanent, unique |
| name | String | PRE-007 name rules (1-60 characters, unique folded among smart collections) |
| match | `all` \| `any` | unknown values read as `all` |
| conditions | [PresetSmartCondition] | ≤ 32 |

## PresetSmartCondition
| Field | Type | Rules |
|---|---|---|
| kind | String | `tag`, `notTag`, `pack`, `motion`, `color`, `favorite`; others kept, skipped |
| values | [String] | ≤ 64, each 1-128 characters, de-duplicated (tags folded) on save; empty for `favorite` |

## Document `smart-collections.json`
```json
{ "schemaVersion": 1, "smartCollections": [ { "id": "smart-…", "name": "Calm", "match": "all",
  "conditions": [ { "kind": "tag", "values": ["Calm"] } ] } ] }
```
Sorted keys, unescaped slashes; ≤ 1 MiB; depth ≤ 8.

## PresetSmartContext (in memory)
library listing, `PresetTagIndex`, favorites `Set<String>`, `PresetColorFilter`, `PresetEnergyFilter`.

## State transitions
create → (edit rules | rename)* → delete. Every change is applied to a copy, saved, then shown.
