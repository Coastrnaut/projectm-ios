# Contract: PRE-008 Smart Collections

## C1 Matching (`PresetSmartMatcher.members(of:in:)`)
- Input: a `PresetSmartCollection` and a `PresetSmartContext`. Output: `[String]` preset IDs.
- `tag`: listed presets carrying any value (folded). `notTag`: listed presets carrying none. `pack`: `source` ∈ values.
  `motion`: PRE-005 class ∈ values. `color`: families ∩ values ≠ ∅. `favorite`: favorites that are listed.
- `all` = intersection, `any` = union of the known conditions; none known → `[]`.
- Order: `PresetLibrary.alphabeticalListing`; each ID once; each non-empty hash once (first kept).

## C2 Document (`PresetSmartCollectionsFile`)
- `schema`: `org.projectmios.preset-smart-collections`, versions 0…1, 1 MiB, depth 8, strings 4 KiB, 4,096 elements.
- `decode(_:migrations:)` → `(file, migratedFrom)`; throws `newerVersion(v)` or `unreadable`; duplicate or empty IDs are unreadable.
- `encode()` stable bytes.

## C3 Store (`PresetSmartCollectionStore`)
- `init(directory:makeID:write:migrations:)`; `availability` (`available` / `newerFormat(version:)`); `loadNotice`.
- `create(name:match:conditions:)`, `update(_:match:conditions:)`, `rename(_:to:)`, `delete(_:)`; errors are `PresetCollectionError` (+ `tooManyConditions`, `invalidCondition` as `PresetSmartCollectionError`).
- Unknown condition kinds pass through every change unchanged.

## C4 App
- `PresetCoordinator.smartCollections`, `smartListing(_:)`, `smartCount(_:)`, `draftCount(match:conditions:)`, `createSmartCollection`, `updateSmartCollection`, `renameSmartCollection`, `deleteSmartCollection`.
- Accessibility identifiers: `newSmartCollection`, `smartCollection:<name>`, `smartName`, `smartMatch`, `smartRule:<kind>:<value>`, `smartRule:favorite`, `smartDraftCount`, `smartSave`, `editSmartRules`.

## C5 Backup
- Record path `collections/smart-collections.json`; records key `smart-collections`; restore entries `smart/<id>` in section `collections`.
