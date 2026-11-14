# Research: PRE-006 Recently Played History

Decisions taken by Claude under owner rules 4 and 9 (conservative, local-first).

## PRE-006-D1 — Storage: one UserDefaults key

- **Decision**: `recentPresets`, a `[String]` of at most 50 preset IDs, most recent first.
- **Rationale**: Favorites and `lastPresetID` already live in UserDefaults; one small value is written
  atomically; FILE-005 and FILE-011 already classify keys; the device privacy check already lists keys.
  A file next to `tags.json` would ride along in FILE-005's collections folder copy and need its own
  versioned format for 50 strings.
- **Alternatives**: a `history.json` in `PresetCollections/` (rejected: backed up with the folder,
  more code); SQLite (rejected: overkill, roadmap's suggestion is "SQLite or JSON").

## PRE-006-D2 — Content and limits

- **Decision**: IDs only; order is the only time information; capacity 50; re-showing moves to front;
  reading drops non-strings, empty and duplicate IDs (first kept) and trims to 50.
- **Rationale**: the least data that answers "what did I just watch"; no timestamps means nothing to
  reconstruct a listening timeline from.
- **Alternatives**: timestamps for "Today/Yesterday" grouping (rejected: more personal data, no
  acceptance need); play counts (rejected, same reason).

## PRE-006-D3 — What counts as played: a 3 s dwell

- **Decision**: after a successful load, the preset becomes the dwell candidate with the monotonic time;
  a scheduled check 3 s later records it if it is still the candidate and the time has passed. A newer
  load replaces the candidate; a failed load never becomes one; turning history off or clearing cancels
  it. Any cause of the switch counts. The clock (`ProcessInfo.systemUptime`) and the scheduler are
  injected, so tests drive time explicitly.
- **Rationale**: Random flicks under 3 s record nothing; a timer (not "on the next switch") means the
  last preset of a session is also recorded.
- **Alternatives**: record on load (rejected: every flick); record on leave (rejected: loses the last
  preset if the app is killed); 10 s (rejected: too slow to feel responsive; 3 s matches the roadmap's
  example).

## PRE-006-D4 — Opt-out

- **Decision**: `settings.recentPresets.enabled`, absent = on. Off removes `recentPresets` and cancels
  the candidate; on starts empty. At launch, an off switch removes any history (covers a FILE-005
  restore that brought the switch back off).
- **Rationale**: the roadmap says opt-out (default on); clearing on opt-out is what a user who turns it
  off expects.

## PRE-006-D5 — Backup, erase, privacy

- **Decision**: `recentPresets` is a FILE-005 excluded key (never backed up, never restored); the switch
  is included (a preference) and so erased with Settings. FILE-011 erases the history with favorites;
  the category is renamed "Collections, tags, favorites and history" and its count includes history
  entries. An ADR amends FR-065 and FR-123 for these two keys only; the privacy policy lists the
  history; `ALLOWED_KEYS` gains both keys.
- **Alternatives**: back the history up (rejected: personal usage data should not travel); erase it
  with Settings (rejected: it is library-usage data, next to favorites, and the Settings category is
  for preferences).

## PRE-006-D6 — UI placement and scope

- **Decision**: a "Recently Played" row on the browser home (after My Presets) opens the list; rows are
  the standard `PresetRow`. Choosing one plays it in the current scope (`choose(preset, from: scope)`),
  so Next and Random keep walking the list the user was in. Settings gets a "Recently Played" section
  with the switch and Clear History. Announcements on the library lane.
- **Alternatives**: a third segment "Recent" in the All/Favorites picker (rejected: the picker is bound
  to a Bool used across features and tests); a `PresetScope.recent` (rejected: the list reorders as it
  is walked).
