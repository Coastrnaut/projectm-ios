# Research: PRE-018 Preset integrity scanner

- **PRE-018-D1 Textures.** Decision: re-run `MilkdropPresetValidator.validate` on each waiting or
  playable stored text with the bundled texture names (`UserPresetsCoordinator.textureNames`, passed in
  through the import context) and take its `missingTexture` warnings. Rationale: one definition of
  "missing texture" for import and scan (engine names, two-letter prefixes, `randNN`). The app has no
  user textures (PRE-012/013 import `.milk` only), so the suggestion is honest: blank texture, keep it,
  quarantine or remove. Alternatives: reuse the warnings stored at import (stale when the bundled list
  changes); add user textures (out of scope: storage, licences, engine search path per preset).
- **PRE-018-D2 Unparsable.** Decision: the same validator call; a non-nil `rejection` on a waiting or
  playable preset is an unparsable issue with the rejection's message. Rationale: limits were tightened
  over time (PRE-012 complexity limits); stored presets were never re-judged.
- **PRE-018-D3 Missing file.** Decision: the stored file must exist, have the record's byte count and
  SHA-256. Absent, unreadable, wrong size or wrong hash is one kind ("missing or damaged"). Size is
  checked before reading; files over `PresetImportLimits.maxFileBytes` are not read.
- **PRE-018-D4 Relink by checksum (MED-013 pattern).** Decision: `UserPresetLibrary.relink(id, data)`
  accepts bytes only when SHA-256 and size equal the record's, then writes `files/<sha>.milk`
  atomically; the record is unchanged (same ID, state, trial history). A bundled duplicate whose stored
  SHA-256 equals `duplicateOf.sha256` can be restored from the bundled bytes (the app reads them with
  the existing `bundledData` loader), through the same call. Rationale: the bytes were already checked
  and tried; identity is proven by the hash.
- **PRE-018-D5 Dangling.** Decision: an ID is known when the full library (`PresetLibrary.preset(id:)`,
  bundled presets incl. locked packs) or any user preset record (all states) names it. When the user
  preset list is unavailable (newer format), user-prefixed IDs are never judged dangling. Rationale: no
  false positives that would delete a user's favorites.
- **PRE-018-D6 Off main.** Decision: inventory inside the `UserPresetLibrary` actor; the scanner is a
  pure static function run in a detached utility task; the coordinator only copies references on the
  main actor and awaits. A second scan cannot start while one runs.
- **PRE-018-D7 Bounds.** 1,200 records (1,000 waiting/playable + 200 quarantined), 128 MiB text read,
  60,000 references, 500 issues, 8 textures per preset. Past one, that part stops and the report is
  `incomplete`. Tests inject small limits.
- **PRE-018-D8 Fix All Safe.** Decision: remove dangling references only, grouped per store (one save
  per store). Remove Preset and Move to Quarantine are per issue with a confirmation dialog.
- **PRE-018-D9 UI place.** Decision: My Presets row "Check Library" → `UserPresetRoute.check`. Rejected:
  Settings → Storage (MED-013's place) because the issues are about presets, and My Presets already holds
  Quarantine and Remove.
- **PRE-018-D10 Recents.** `RecentPresetHistory.removing(_:)` and `RecentPresetsStore.remove(_:)`; the
  coordinator's `ids` refresh. No key change.
