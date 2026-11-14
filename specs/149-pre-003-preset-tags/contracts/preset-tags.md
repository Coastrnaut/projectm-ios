# Contract: PRE-003 Preset Tags

## C1 Model (PresetLibrary)

- `PresetTagMap.normalizedTag(_:) -> String?`, `fold(_:)`, `tags(of:)`, `has(_:tag:)`,
  `add(_:to:) throws(PresetTagError) -> String` (returns the stored spelling), `remove(_:from:) throws(PresetTagError)`,
  `prune(_ presetID:)`, `repaired(_:) -> (map, dropped)`.
- `PresetTagError`: `invalidTag`, `alreadyTagged(String)`, `notTagged(String)`, `tooManyTags(limit:)`,
  `tooManyDistinctTags(limit:)`, `tooManyTaggedPresets(limit:)`, `newerFormat`, `saveFailed`; each has `message` (`saveFailed`: "Your tags could not be saved."; `newerFormat`: "These tags were saved by a newer version of the app. Update the app to use them.").

## C2 File and store

- `PresetTagsFile.decode(_:) throws -> (map, dropped)` (`ReadError.newerVersion(Int)`, `.unreadable`);
  `PresetTagsFile(map:).encode()`.
- `PresetTagStore(directory:write:)`: `map`, `availability`, `loadNotice`, `add`, `remove`, `prune`;
  every change saved atomically before it is visible.

## C3 Index and library

- `PresetTagIndex(map:isListed:)`: `vocabulary`, `count(of:)`, `matching(all:) -> Set<String>`,
  `visitedCount` (of the last `matching`), `presetIDs(tagContaining:)`.
- `PresetScope.tagged([String])` (storage `all`); `PresetLibrary.taggedListing(_:index:)`,
  `members(of:…tags:)`, `title(of: .tagged)` = "Tagged: a, b", `search(_:limit:tagMatches:)`.

## C4 App

- `PresetCoordinator`: `tags(of:)`, `tagVocabulary`, `selectedTags`, `toggleTag`, `clearTags`,
  `taggedListing`, `addTag(_:to:) -> Bool`, `removeTag(_:from:) -> Bool`, `pruneTags(_:)`,
  `tagsMessage`, `tagsNotice`; announcements: "Tagged <name> <tag>.", "Removed tag <tag> from <name>.",
  refusals with the error message (library lane); "<n> presets with these tags" (search lane).
- Identifiers: `presetTagChips`, `presetTagChip.<tag>`, `presetTagClear`, `presetTags` (sheet),
  `presetTagField`, `presetTagAdd`, `presetTag.<tag>`, `presetTagRemove.<tag>`,
  `presetTagSuggestion.<tag>`, `presetTagsDone`, `taggedEmpty`; context menu item "Tags…".

## C5 Backup

- Record `collections/tags.json`; `LibraryContents.presetTags`; restore section `tags`.
