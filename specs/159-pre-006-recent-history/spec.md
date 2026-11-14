# Feature Specification: PRE-006 Recently Played History

**Feature Branch**: `feature/pre-006` (spec directory `159-pre-006-recent-history`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row PRE-006 (P1, size S, extension of the existing favorites). Observable behavior,
verbatim: "Track recent preset IDs locally with opt-out and clear control." Acceptance, verbatim:
"Clear deletes history and does not alter favorites."

Identifiers carry the roadmap ID: requirements `PRE-006-R1…`, success criteria `PRE-006-S1…`, tasks
`PRE-006-T01…`. Other features are cited by their own IDs: feature 001 FR-065 and feature 002 FR-123
(persistence limits), FR-116 (choosing from a list sets the scope), PRE-007 (collections), PRE-003
(tags), FILE-005 (library backup), FILE-011 (erase), ACC-004 (announcements and row labels).

## Baseline: what exists today (audit of 2026-11-14, commit `46265f7c`)

The audit confirms the gap: the app keeps no record of which presets were shown, apart from the
single last-selected preset.

| Area | Today |
|---|---|
| Favorites | `FavoritesStore`: UserDefaults keys `favorites` (preset IDs, sorted) and `lastPresetID` (written on every successful load). Its header says nothing else about presets or listening is stored (FR-065). |
| Persistence rule | Feature 001 FR-065 and feature 002 FR-123: "No listening history, recently played list, or purchase data is stored by the app." The privacy policy repeats it. This row needs an amendment (an ADR). |
| Browser | `PresetBrowserView`: All/Favorites picker, PRE-003 tag chips, library home (Included, packs, All A-Z, Collections, My Presets). No "Recent" scope or list exists; `PresetScope` has no recent case. |
| Collections and tags | PRE-007 `collections.json` and PRE-003 `tags.json` in `Application Support/PresetCollections/`. |
| Backup (FILE-005) | `LibrarySettingsPolicy.includedKeys` (backed up) and `excludedKeys` (read, deliberately left out). |
| Erase (FILE-011) | Six categories; "Collections, tags and favorites" removes the `PresetCollections` folder and the `favorites` key. A package test requires every FILE-005 key to be erased by exactly one category or deliberately kept. |
| Device privacy check | `scripts/run_device_tests.py` `ALLOWED_KEYS`: every UserDefaults key the app may write. |
| Announcements | `AccessibilityAnnouncer` lanes; tag and import edits use the `library` lane. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option that still delivers the roadmap row.

- Q: Where is the history kept? → A: In UserDefaults under one new key, `recentPresets` (an array of preset ID strings, most recent first), beside `favorites` and `lastPresetID`. A key, not a file next to `tags.json`: the list is small (at most 50 short IDs), it is written as one value atomically, and keeping it out of the `PresetCollections` folder means FILE-005's folder record never carries it.
- Q: What is stored per entry? → A: The preset ID only. Order is the only time information; no dates, durations, play counts, audio source or app names.
- Q: How long is the list? → A: At most 50 distinct IDs, most recent first. Showing a preset already in the list moves it to the front (de-duplicated); the 51st distinct ID drops the oldest.
- Q: What counts as played? → A: A preset that stayed on screen for at least 3 seconds after it loaded successfully, whatever chose it (the user, Next, Previous, Random, the launch preset, a play queue, OSC or MIDI). Flicking through Random faster than that records nothing. A preset that failed to load is never recorded. The dwell is measured on an injected monotonic clock.
- Q: Opt-out? → A: A Settings switch "Remember Recently Played", on by default (the roadmap row says opt-out), stored under `settings.recentPresets.enabled`. Turning it off stops recording at once and clears the existing history; turning it on again starts from an empty list.
- Q: Clear control? → A: "Clear History" (in Settings and at the bottom of the Recent list) asks for confirmation in a destructive alert, then removes the history only. Favorites, `lastPresetID`, the scope, tags and collections are untouched.
- Q: Where is the history shown? → A: A "Recently Played" row on the browser's library home (with its count) opens the Recent list: most recent first, locked presets marked (FR-114's way), presets no longer in the library left out. Choosing a preset there plays it without changing the scope (the list reorders itself as presets are played, so it is not a stable scope to walk).
- Q: Is history backed up or erased? → A: Not backed up: it is personal usage data, so `recentPresets` joins FILE-005's excluded keys (a restore never brings history from another device). The opt-out switch is a normal setting: backed up and erased with Settings. FILE-011 erases the history with favorites; the category is renamed "Collections, tags, favorites and history" so the user can see that.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I find the presets I just watched (Priority: P1) — MVP

A VJ flicks through Random, stays on two presets they like, and later opens the browser's "Recently
Played" list: both are at the top, newest first, and tapping one plays it again.

**Why this priority**: It is the row's behavior.

**Independent Test**: Drive the recorder with an injected clock: presets shown for 3 s or more are
listed newest first, shorter ones are not; the list survives recreating the store from UserDefaults.

**Acceptance Scenarios**:

1. **Given** preset A is shown for 3 s and then B for 3 s, **When** the Recent list opens, **Then** it lists B, then A.
2. **Given** preset C is shown for 1 s before the next switch, **When** the Recent list opens, **Then** C is not listed.
3. **Given** A, B, A were each shown for 3 s, **When** the list is read, **Then** it is A, B (no duplicate).
4. **Given** 51 distinct presets were shown, **When** the list is read, **Then** it holds the 50 newest.
5. **Given** a history, **When** the app is relaunched, **Then** the same list is shown.

---

### User Story 2 - I clear the history without losing my favorites (Priority: P1)

**Independent Test**: Seed favorites, the last preset, tags and history; clear; history is empty and
everything else is byte-identical.

**Acceptance Scenarios**:

1. **Given** favorites, a last preset, tags and a history, **When** the user confirms Clear History, **Then** the history is empty, `favorites` and `lastPresetID` are byte-identical and the tags file is unchanged.
2. **Given** the confirmation alert, **When** the user cancels, **Then** nothing changes.
3. **Given** a clear, **When** it completes, **Then** VoiceOver announces "Recently played history cleared."

---

### User Story 3 - I turn history off (Priority: P2)

**Independent Test**: With the switch off, presets shown for 3 s or more are not recorded and the old
history is gone.

**Acceptance Scenarios**:

1. **Given** a history, **When** "Remember Recently Played" is turned off, **Then** the history is empty and the Recent list says history is off.
2. **Given** the switch is off, **When** presets are shown for 3 s or more, **Then** nothing is recorded.
3. **Given** the switch is turned on again, **When** a preset is shown for 3 s, **Then** only it is listed.

### Edge Cases

- A preset still dwelling when history is turned off or cleared is not recorded afterwards.
- A recorded preset that later leaves the library (a removed user preset) is not listed; its ID stays until it ages out, is cleared or erased.
- A recorded preset of a pack that became locked (refund) is listed with a lock; choosing it opens the purchase sheet (FR-106).
- A flagged preset chosen from Recent while Reduce flashing is on is warned first (ACC-002-R6).
- A stored value that is not a list of strings, or holds empty or duplicate IDs or more than 50 entries, is read leniently: invalid entries dropped, duplicates kept once, trimmed to 50.
- FILE-005 restore never writes `recentPresets`; FILE-011 erase of "Collections, tags, favorites and history" removes it.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-006-R1**: The app MUST keep a local, ordered, de-duplicated list of at most 50 preset IDs, most recent first, under the UserDefaults key `recentPresets`. Nothing but the IDs is stored.
- **PRE-006-R2**: A preset MUST be recorded when it stays on screen for at least 3 s after a successful load; leaving it earlier (another preset, a failure does not leave it) records nothing; a failed load records nothing. Recording moves an existing ID to the front.
- **PRE-006-R3**: A Settings switch "Remember Recently Played" (default on, `settings.recentPresets.enabled`) MUST control recording; turning it off MUST clear the history and cancel any pending recording.
- **PRE-006-R4**: "Clear History" MUST ask for confirmation, then remove only the history; favorites, `lastPresetID`, the scope, tags and collections MUST be unchanged.
- **PRE-006-R5**: The browser home MUST offer "Recently Played" with its count, opening a list newest first (locked presets marked, presets not in the library left out), with an empty state ("No recently played presets yet." or, when off, "Recently played history is off.") and "Clear History". Choosing a preset there plays it without changing the scope.
- **PRE-006-R6**: Every new control MUST have an accessible label (the row: "Recently Played, 2 presets"); a clear and the switch's change are announced on the shared announcer's library lane.
- **PRE-006-R7**: The history MUST NOT be backed up (FILE-005 excluded key); the switch is backed up and erased with Settings; FILE-011's "Collections, tags, favorites and history" erases the history, and the category's count includes it.
- **PRE-006-R8**: Stored values MUST be read leniently (non-strings, empty and duplicate IDs dropped; trimmed to 50).
- **PRE-006-R9**: This amends feature 001 FR-065 and feature 002 FR-123 for exactly these two keys (ADR); the privacy policy and the device privacy check's allowed keys are updated; nothing leaves the device and no networking is added.

### Key Entities

- **Recent history**: ordered list of preset IDs (stored).
- **Dwell candidate**: the preset on screen and the monotonic time it loaded (in memory).
- **Remember switch**: a Boolean user setting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-006-S1**: After Clear History, the history is empty while favorites and `lastPresetID` are byte-identical and the tags file's bytes are unchanged (acceptance test).
- **PRE-006-S2**: 100% of presets shown for 3 s or more are recorded and 0% of those shown for less (injected-clock tests).
- **PRE-006-S3**: With the switch off, 0 presets are recorded and the history is empty.
- **PRE-006-S4**: A UI test plays two presets, sees them in Recently Played, clears, and sees Recent empty while Favorites still lists its item, in under 30 s.

## Assumptions

- Recording automatic switches (launch preset, OSC, MIDI, play queue) is intended: the list answers "what was on screen".
- Simulator and Mac results are not device evidence; this row needs no device-only check.
- Grouping by date, per-preset play counts and syncing are out of scope.
