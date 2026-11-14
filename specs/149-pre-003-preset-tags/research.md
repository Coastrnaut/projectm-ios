# Research: PRE-003 Preset Tags

## PRE-003-D1 Storage location and store behaviour

- **Decision**: `Application Support/PresetCollections/tags.json`, managed by `PresetTagStore`, which
  copies `PresetCollectionStore`'s transaction model: each change is applied to a copy, saved
  atomically, then shown; a failed save throws and changes nothing; a newer-version file makes the
  store unavailable (no write); an unreadable file is moved to `tags.unreadable.json` (one copy) with
  a one-time notice; if it cannot be moved, saving is blocked.
- **Rationale**: the same folder is already wired into FILE-005 restore staging (the live folder is
  copied before changes), FILE-009 Storage (Presets), FILE-010 protected roots, FILE-011 erase and the
  UI-test reset; no new UserDefaults key (constitution privacy constraints, no allowed-key churn).
- **Alternatives**: UserDefaults (unbounded plist growth, settings backup semantics, not a library
  record); writing into `collections.json` (would change PRE-007's format and version).

## PRE-003-D2 Tag rules

- **Decision**: SCN-005's rules verbatim (trimmed 1-40 characters, no line breaks or control
  characters, fold with `[.caseInsensitive, .diacriticInsensitive, .widthInsensitive]` and `nil`
  locale, 16 per item, 256 distinct, existing spelling adopted, tags sorted by (fold, text)) plus a
  20,000 tagged-preset cap and a 4 MiB file cap. Implemented in PresetLibrary (not imported from
  ShowControl, which PresetLibrary must not depend on); a test checks the two folds agree on samples
  in the app test target, which links both.
- **Alternatives**: a shared package for tags (a new package for ~150 lines; rejected).

## PRE-003-D3 Inverted index

- **Decision**: `PresetTagIndex(map:isListed:)` builds `folded tag → Set<preset ID>` for listed IDs
  only, plus the display spelling per folded tag (smallest by (fold, text)). `matching(all:)` sorts
  the selected sets by size and intersects starting from the smallest; it reports how many IDs it
  visited, so a test asserts the cost is bounded by the matching sets, not the library. The browser
  then maps IDs to presets through the library's ID lookup and sorts alphabetically. Rebuilt only
  when the tags or the library change (a version counter).
- **Rationale**: chip changes must stay instant with 12,847 presets; a linear scan of every preset's
  tag list per change is avoidable.

## PRE-003-D4 Lenient decoding

- **Decision**: bytes are first checked against a `DocumentSchema` (4 MiB, depth 4,
  strings ≤ 4 KiB, ≤ 20,000 elements per object, no duplicate keys, strict UTF-8). Version > 1 →
  `newerVersion`; missing or < 1 → unreadable (no migrations yet). The `tags` object is decoded per
  entry: a non-list value, a non-string item, an empty ID, an invalid or non-normalized tag, a
  duplicate, a 17th tag, a 257th distinct tag or entries past 20,000 are dropped and counted; entries
  are visited in sorted ID order so repair is deterministic.

## PRE-003-D5 Scope and search

- **Decision**: `PresetScope.tagged([String])` holds the selected display tags; members are the
  index's matching presets, alphabetical, playable only; stored as `all` (like `search`). Search adds
  `tagMatches`: the IDs carrying any tag whose folded text contains the folded needle (at most 256
  tags scanned), checked alongside the name/author key during the existing scan; chips then filter
  the groups.

## PRE-003-D6 Backup, restore and erase

- **Decision**: a separate backup record `collections/tags.json` (the same document bytes) and a
  `LibraryContents.presetTags` field (nil without a file). Restore section `tags`, one entry per
  preset ID ("tags/<id>"): new → add; identical → keep; clash → Keep both = folded union in stored
  order capped at 16 (fell back when capped), Replace = backup's list, Skip = device's. Tags of a user
  preset that the presets section adds as a copy under a derived ID follow that ID. The install
  writes the merged document into the staged `PresetCollections` folder. The backup format version
  stays 1: no release has shipped FILE-005, so no older reader exists (documented in the format
  header). FILE-011 erase already deletes the whole folder; the category title becomes "Collections,
  tags and favorites".

## PRE-003-D7 Orphans

- **Decision**: tags of IDs the library does not list are kept and hidden (index built over listed
  IDs only); locked-pack presets are listed, so their tags are visible; removing a user preset prunes
  its tags (an explicit deletion). Rejected: pruning at every launch (a user preset waiting for its
  check or a temporarily missing pack would lose tags).
