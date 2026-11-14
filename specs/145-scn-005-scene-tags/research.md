# Research: SCN-005 Scene Tags

## SCN-005-D1: where tags live

- **Decision**: In `show.json` as optional `sceneTags` (scene ID → array of tag strings), beside
  SCN-004's `folders` and `sceneFolders`.
- **Rationale**: Scene files stay byte-identical (no SCN-001 change, no QA-004 field, no SCN-013
  migration); one atomic index write per edit; backup and import already carry the index.
- **Alternatives**: a `tags` field in each scene document (changes canonical scene bytes and every
  archive; duplicate copies and imports would carry tags across shows); a separate `tags.json`
  (a second file to keep in step and to back up).

## SCN-005-D2: vocabulary and identity

- **Decision**: Implicit vocabulary (union of assignments). Identity is SCN-004's fold
  (`.caseInsensitive, .diacriticInsensitive, .widthInsensitive`, `nil` locale). Adding a tag that
  folds equal to an existing one adopts the existing spelling. Vocabulary display for several stored
  spellings: the smallest by (fold, text).
- **Alternatives**: stored vocabulary (orphans, repair, a second list); case-sensitive tags (users
  get "Live" and "live" side by side).

## SCN-005-D3: limits and order

- **Decision**: 1-40 characters after trimming, one line, no control characters; 16 per scene; 256
  distinct per show. Each scene's tags sorted by (fold, text). Worst case 256 scenes × 16 × ~45 bytes
  ≈ 185 KB, well under the 1 MiB show file limit together with folders.

## SCN-005-D4: encoding and repair

- **Decision**: Written only when non-empty after pruning to the show's scene IDs (a show without
  tags encodes exactly as before; JSON keys are sorted so `sceneTags` lands deterministically).
  Decoding: a `sceneTags` value that is not an object of string arrays makes the whole key unreadable;
  to keep "the show is never refused", the field is decoded leniently (any JSON) and every entry that
  is not a list of strings counts as dropped. Per scene: unknown scene IDs, invalid tags, folded
  duplicates, tags past 16 per scene and new tags past 256 distinct (scenes in sorted ID order) are
  dropped; `ShowDecodeWarning.droppedTags(n)` reports the count of dropped tags plus dropped entries.
- **Alternatives**: refusing the show (violates SCN-005-R7); silently dropping (no warning to report).

## SCN-005-D5: backup, import, duplicate, delete

- FILE-005 backup re-encodes the index through `ShowCueList` (tags included); exact restore writes it
  back. Merge restore and FILE-004 import decode the existing show, append cues and save: existing
  tags are kept, incoming scenes arrive untagged. No code change; covered by a round-trip test.
- Duplicate Scene copies the source's tags (`ShowCueList.copyTags`) right after inserting the copy.
- A scene leaving the show (last cue removed) loses its tags at the next save via pruning in
  `encoded()`; the in-memory map is pruned in the same save path so the vocabulary updates at once.

## SCN-005-D6: switcher filtering

- **Decision**: Selected tags (folded set, in memory in `SceneSwitcherModel`) combine with AND;
  entries are filtered by tags first, then UIX-002's query ranking runs with tags as an extra
  non-early match field. Selections whose tag left the vocabulary are ignored and pruned on the next
  toggle or open. Chip changes call the same re-highlight and count announcement as a query change.
- **Alternatives**: OR (widens the list; a performer narrowing a set wants AND); a separate filter
  screen (slower than chips in the quick switcher).
