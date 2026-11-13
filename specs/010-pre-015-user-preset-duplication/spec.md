# Feature Specification: PRE-015 User preset duplication

**Feature Branch**: `feature/pre-015` (spec directory `010-pre-015-user-preset-duplication`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement PRE-015 (User preset duplication) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Clone a bundled preset into editable user space without altering original." Acceptance, verbatim: "Editing clone leaves bundled hash unchanged." Dependencies: PRE-012 (integrated). Honor the repository constitution."

**Roadmap row**: PRE-015, priority P0, effort M, depends on PRE-012
(`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PRE table). Later rows build on it and are out of scope
here: PRE-014 (export of user presets), PRE-016 (parameter overrides), PRE-017 (restore points),
PRE-018 (integrity scanner).

**ID convention**: requirements are `PRE-015-R1…`, success criteria `PRE-015-S1…`, tasks
`PRE-015-T01…`. FR-065 and FR-106 cite feature 001 and feature 002
(`specs/001-ios-projectm-visualizer/spec.md`, `specs/002-preset-library-unlock/spec.md`);
`PRE-012-…` cites `specs/008-pre-012-preset-import-validation/spec.md`; `PRE-007-…` cites
`specs/005-pre-007-preset-collections/spec.md`.

## What already exists (audit of HEAD `85e5c9e`, 2026-11-12)

| Area | What HEAD does | Evidence | Gap |
|---|---|---|---|
| Bundled presets | 28 Included files in the app bundle and 12,913 pack presets in a read-only archive inside the bundle; each has a stable id and a content hash in the index. | `PresetLibrary.swift`, `PresetArchive.swift`, `RendererPresetLoader` | No way to get an editable copy. |
| User presets | Imported `.milk` files are copied into app storage named by content hash, statically validated, tried on an off-screen engine, then playable in "My Presets" or quarantined (PRE-012). The record is a versioned file (version 1). | `UserPresetStore.swift`, `UserPresetLibrary.swift`, `UserPresetsFile.swift` | A user preset cannot be created from a bundled one, and no preset text can be edited. |
| Copies of built-in presets | An import whose content equals any built-in preset (locked or not) is refused (PRE-012-R5). | `UserPresetLibrary.importFile` | Stays for imports; duplication is a separate, lock-aware path. |
| Lock boundary | Locked pack presets ask for the purchase instead of playing (FR-106); user presets are never locked. | `PresetCoordinator.choose`, `PresetLibrary.isLocked` | A copy of a locked preset would bypass the purchase unless it carries the lock. |
| Text editing | None in the app. | — | Needed: the acceptance edits the clone. |
| Corpus facts | 2 bundled presets have a shader with unbalanced braces, which PRE-012's validator quarantines (`docs/test-reports/preset-import.md`). 37 bundled files are not valid UTF-8; 3,740 use CRLF line endings. | PRE-012 corpus check | Duplicating these must give a clear outcome. |

## Clarifications

### Session 2026-11-12

Answered under the standing delegation (recommended option first; no owner question was needed).
Each answer is the conservative, local-first choice.

- Q: What happens to an existing copy of a locked-pack preset when the purchase is refunded or
  revoked? → A: It is held, not deleted: listed in My Presets as needing the full library, not
  playable, not editable, not in any scope; tapping it offers the purchase; it plays again when
  the entitlement returns. (Rejected: deleting it, which destroys user work; leaving it playable,
  which turns duplication into a way around the purchase.) Applied in R7, R8, US3, S4.
- Q: What happens when the user duplicates a preset whose unchanged copy is already in My
  Presets? → A: Refused, naming the existing copy; nothing is stored. Numbered names ("copy 2")
  are used when an earlier copy was edited or renamed and its name is taken. (Rejected: a second
  record sharing the same text, which needs shared-file bookkeeping in quarantine and removal for
  no user benefit.) Applied in R3, R6, US1 scenarios 2-3.
- Q: When an edit fails a check, is it saved as invalid or not saved at all? → A: Not saved: the
  stored file and record stay byte-identical, the editor stays open with the user's text and the
  reason, and the last good version keeps playing. If the check is impossible right now (no
  off-screen engine, app in the background), the save is refused with "try again"; the edit is
  never stored unchecked. Applied in R11-R13, S5.
- Q: Does the user-preset record change format, and how? → A: Version 2, with a pure migration
  from version 1 that only raises the version (the new fields are optional and absent in migrated
  records). A plain additive change without a version bump was rejected: a version-1 reader
  cannot decode the new origin value and would set the whole record aside as unreadable, and it
  would not enforce the lock on copies. With version 2, PRE-012's reader reports "saved by a
  newer version" and changes nothing. Applied in R21.
- Q: What happens when a bundled preset that PRE-012's validator would quarantine (2 such files
  in the packs) is duplicated? → A: The duplicate is refused with the validator's reason and
  nothing is stored; the built-in preset is unaffected and still plays. (Rejected: storing the
  copy in Quarantine, where it could never be fixed because quarantined files are not editable.)
  Applied in R5, US1 scenario 4.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Duplicate a bundled preset into My Presets (Priority: P1)

A user likes a built-in preset and wants a version of their own. From the preset browser (any
list that shows the preset) or from the visualizer while it plays, they choose "Duplicate to My
Presets". A copy named "<original> copy" appears in My Presets and plays there; the built-in
preset is listed, starred and played exactly as before.

**Why this priority**: it is the roadmap row's observable behavior and the basis of editing.

**Independent Test**: duplicate an Included preset; the copy is listed in My Presets with its
own id, plays, and the bundled preset's bytes, hash, index entry and favorites are unchanged.

**Acceptance Scenarios**:

1. **Given** a playable bundled preset "Alpha", **When** the user chooses Duplicate to My
   Presets, **Then** "Alpha copy" is added to My Presets, the result is announced, and the
   bundled "Alpha" still plays from the app's own files.
2. **Given** "Alpha copy" exists and is unchanged, **When** the user duplicates "Alpha" again,
   **Then** nothing is added and the message names the existing copy.
3. **Given** "Alpha copy" exists and was edited, **When** the user duplicates "Alpha" again,
   **Then** "Alpha copy 2" is added.
4. **Given** a bundled preset whose text fails the import checks (for example a shader with
   unbalanced braces), **When** the user duplicates it, **Then** nothing is added and an alert
   says why, in the same words an import would use.
5. **Given** the preset currently on screen is bundled, **When** the user taps Duplicate in the
   controls, **Then** the same happens as from the browser; the visualizer keeps playing the
   bundled preset.

---

### User Story 2 - Edit my copy without touching the original (Priority: P1)

The user opens their copy, changes its text (for example a zoom value), and saves. The change
is checked before it can play; after saving, the copy plays with the change, and the bundled
original is byte-for-byte what shipped.

**Why this priority**: the acceptance criterion ("Editing clone leaves bundled hash unchanged").

**Independent Test**: duplicate, edit, save; the copy's stored file and hash change to the saved
text; the bundled file and its index hash are identical before and after.

**Acceptance Scenarios**:

1. **Given** a playable user preset, **When** the user chooses Edit, changes the text and taps
   Save, **Then** the text is checked by the same static checks and engine trial as an import and,
   if both pass, the new text is stored, the preset plays the new text, and the bundled original
   is unchanged.
2. **Given** an edit that fails a check, **When** the user taps Save, **Then** nothing is stored,
   the editor stays open with the user's text and shows the reason, and the last saved version
   keeps playing.
3. **Given** unsaved changes, **When** the user taps Cancel, **Then** they are asked to discard
   the changes or keep editing; discarding changes nothing. Swiping the editor down does not
   close it while there are unsaved changes.
4. **Given** the app ends while an edit is being checked, **When** it starts again, **Then** the
   edit is discarded, the user is told once, and the last saved version is still playable (it is
   not quarantined).
5. **Given** VoiceOver or the largest accessibility text size, **When** the user edits and saves,
   **Then** every control has a label, the text can be read and changed, and the layout fits.

---

### User Story 3 - The purchase boundary holds for copies (Priority: P1)

A preset in a locked pack cannot be duplicated before the library is unlocked: choosing
Duplicate opens the purchase sheet, like playing it would. After a purchase, copies of pack
presets can be made. If the purchase is later refunded or revoked, those copies stay in My
Presets but cannot be played, opened in the editor or chosen by Next/Previous/Random until the
library is unlocked again; nothing the user made is deleted.

**Why this priority**: duplication must not become a way around the paid unlock (ADR-0007).

**Independent Test**: with the library locked, duplicate a pack preset: purchase sheet, nothing
stored. Unlock, duplicate, revoke: the copy is listed as needing the full library and does not
play; unlock again: it plays.

**Acceptance Scenarios**:

1. **Given** a locked pack preset, **When** the user chooses Duplicate, **Then** the purchase
   sheet opens and nothing is stored.
2. **Given** a copy of a pack preset and a revoked purchase, **When** the user taps it, **Then**
   the purchase sheet opens instead of playing it, and Edit is not offered.
3. **Given** that revoked state, **When** the purchase is restored, **Then** the copy plays and can
   be edited again.
4. **Given** a copy of an Included preset, **When** the purchase state changes, **Then** the copy
   is unaffected.

---

### User Story 4 - Know where a copy came from (Priority: P2)

The copy's information view says which built-in preset and pack it was duplicated from, carries
that pack's license statement as written in the app's Licenses screen, says that the app has not
verified any further rights, and shows when it was last edited.

**Why this priority**: attribution and honesty about rights (Constitution IX, ADR-0007).

**Independent Test**: open Information on a copy; the source preset, pack, license statement and
"edited" date are shown.

**Acceptance Scenarios**:

1. **Given** "Alpha copy", **When** the user opens its information, **Then** it names "Alpha", its
   pack, the pack's license statement, and says the copy can be edited on this device.

---

### Edge Cases

- **Locked pack, library unlocked**: allowed; the copy is marked as needing the full library.
- **Refund while a copy plays**: the playing picture keeps playing (as FR-109 does for packs);
  the copy leaves the playable list and cannot be chosen again until the library returns.
- **Duplicate of a preset that failed to load this session**: refused like playing it is; the
  message says it could not be loaded.
- **Source bytes do not match the index hash** (a damaged install): refused, nothing stored.
- **Takedown-listed content**: refused (cannot normally occur: the build already removes it).
- **My Presets full (1,000)** or Quarantine full (200): refused with PRE-012's words.
- **Saved record from a newer app version**: duplicate and edit are refused with PRE-012's
  "newer version" message.
- **Name collision**: "Alpha copy", then "Alpha copy 2", "Alpha copy 3", …, compared without
  regard to case among all user presets; long names are shortened so the result fits 120
  characters.
- **Edit back to the original text** of the copy's own source: allowed (it is still a copy of
  that preset). Edit into the text of a different built-in preset or another user preset:
  refused, naming it (PRE-012-R5 applies to edits as to imports).
- **Edit that grows past 524,288 bytes, or is empty**: refused with PRE-012's words.
- **Non-UTF-8 source (37 bundled files)**: duplicated byte-for-byte; the editor opens it decoded
  as Latin-1 and says that saving stores UTF-8.
- **Edited preset is on screen when saved**: it is reloaded with the new text (and goes through
  PRE-012's first-showing protection again).
- **Remove a copy**: removes only the copy's files; the bundled preset, favorites and collections
  naming the bundled id are untouched; collections naming the copy's id lose it as for any
  removed user preset (PRE-007).
- **Pending copy** (no engine to try it yet, PRE-012-R16): it waits like an import and is not
  editable until it is playable.

## Requirements *(mandatory)*

### Functional Requirements

**Duplicating**

- **PRE-015-R1**: Every row of a bundled preset in the preset browser (home folders, favorites,
  search results, collections) MUST offer "Duplicate to My Presets" as a context-menu item and a
  VoiceOver action. The visualizer controls MUST offer it for the preset on screen when that
  preset is bundled.
- **PRE-015-R2**: A duplicate MUST be a byte-identical copy of the bundled preset's text, read
  from the app's bundled file or archive. Before anything is stored, the copy's content hash MUST
  equal the hash the library index records for that preset; otherwise the duplicate is refused
  and nothing is stored.
- **PRE-015-R3**: The copy MUST get its own permanent `user/<uuid>` id, the bundled preset's
  author, and the name "<original> copy", or "<original> copy N" with the smallest N ≥ 2 that no
  user preset uses (case-insensitive), shortened to fit 120 characters.
- **PRE-015-R4**: The copy's record MUST name its origin: duplicate of the bundled preset id, its
  name, pack id and title, the source content hashes, the pack's license statement verbatim from
  the app's pack metadata, and whether the pack needs the full-library unlock. Rights verified
  MUST be recorded as no; no license is invented.
- **PRE-015-R5**: A duplicate MUST pass PRE-012's static validation. If validation would
  quarantine it, the duplicate MUST be refused with the validator's reason and nothing stored.
  Otherwise it MUST go through PRE-012's engine trial and states (waiting, playable, quarantined)
  exactly like an import, including the crash-loop record and the first-showing protection.
- **PRE-015-R6**: A duplicate whose text equals a user preset already in My Presets or Quarantine
  MUST be refused, naming that entry. PRE-012's limits (1,000 presets, 200 quarantined) and the
  takedown list apply.

**Lock boundary**

- **PRE-015-R7**: A bundled preset the user cannot play (a locked pack before the unlock, or one
  that failed to load this session) MUST NOT be duplicated. For a locked one, Duplicate MUST open
  the purchase sheet, like choosing it to play does (FR-106); for one that failed to load this
  session, Duplicate MUST say so and store nothing. The user-preset library MUST refuse a locked
  one as well, independently of the interface.
- **PRE-015-R8**: While the full-library entitlement is absent, a copy whose source pack needs the
  unlock MUST NOT be playable, editable, readable through the editor, or a member of any scope
  (My Presets, favorites, collections, search). It MUST stay listed in My Presets, marked as
  needing the full library; tapping it opens the purchase sheet; it can be removed or viewed in
  Information. When the entitlement returns, it becomes playable again. Nothing is deleted
  automatically: neither the copy nor a favorite star or collection entry naming it.

**Editing**

- **PRE-015-R9**: A playable user preset (a copy or an import) that is not held by R8 MUST offer
  "Edit" (context menu, swipe action, VoiceOver action). Bundled presets, waiting presets and
  quarantined files MUST NOT be editable.
- **PRE-015-R10**: The editor MUST show the preset's name and full text in editable fields and
  offer Save and Cancel.
- **PRE-015-R11**: Save MUST, in order: check the name (not empty after trimming, at most 120
  characters, cleaned like an imported name); encode the text as UTF-8; refuse an empty text or one
  over 524,288 bytes; refuse text on the takedown list, text equal to a built-in preset other than
  the copy's own source, and text equal to another user preset; run PRE-012's static validation;
  run PRE-012's engine trial on the new text. Only when all pass is the change stored.
- **PRE-015-R12**: A refused or failing save MUST leave the stored preset, its file and its record
  byte-identical; the editor MUST stay open with the user's text and show (and announce) the
  reason. The last saved version keeps playing.
- **PRE-015-R13**: Before the engine trial of an edit, a durable record naming the preset and the
  candidate text MUST be on disk. If the app ends during that trial, the next launch MUST discard
  the candidate, keep the last saved version playable (not quarantined), and tell the user once.
- **PRE-015-R14**: A successful save MUST store the new text under its own content hash, then
  replace the record (new hashes, size, warnings, edit date, not yet proven on screen), and only
  then delete the previous text. If the record cannot be saved, the new file is removed and
  nothing changes.
- **PRE-015-R15**: A name-only change MUST be saved without a trial.
- **PRE-015-R16**: Cancel with unsaved changes MUST ask "Discard Changes" or "Keep Editing";
  without changes it closes at once. While there are unsaved changes (or a save is running),
  swiping the editor down MUST NOT close it (the system offers no hook to ask there; Cancel
  asks).
- **PRE-015-R17**: When the saved preset is on screen, it MUST be reloaded with the new text
  through the normal guarded path (PRE-012-R18, R19).
- **PRE-015-R18**: The editor MUST work with VoiceOver (labelled fields and buttons; the text
  field reads and edits its content) and at every Dynamic Type size, using system text controls.
  The preset text uses a monospaced font that scales with Dynamic Type.

**Integrity of the original**

- **PRE-015-R19**: Neither duplicating nor editing nor removing a copy MUST write to, move or
  delete anything in the app bundle or the preset archive. Every file operation of the user-preset
  store MUST target a path inside the user-preset directory; the store MUST refuse any other path.
- **PRE-015-R20**: The bundled preset MUST keep its id, index entry and hash, and MUST still load
  from the bundle. Favorites and collections that name the bundled id MUST keep naming it; a copy
  is not starred or added to collections automatically.

**Storage**

- **PRE-015-R21**: The user-preset record MUST move to version 2 with a pure, tested migration
  from version 1 (the PRE-012 golden fixture), keeping a backup of the version-1 file until the
  migrated file is saved (PRE-007 rule). A version-1 reader sees a version-2 file as from a newer
  app and does not change it (PRE-012 behavior).
- **PRE-015-R22**: Preset texts MUST stay content-addressed (one file per content hash) with the
  record pointing at the current one, so that PRE-017 can keep earlier versions without a format
  break.

**Privacy and platform**

- **PRE-015-R23**: Amends FR-065 (as amended by FR-123, AUD-001-R22, PRE-007-R17 and
  PRE-012-R30): on-device persistence additionally includes copies of bundled presets the user
  makes, the text the user edits, and the copy's origin. They stay on the device, are never sent
  anywhere, and are deleted when the user removes them or deletes the app. The privacy policy MUST
  say so.
- **PRE-015-R24**: The feature MUST use only public system interfaces, no networking, no new
  entitlement and no new third-party dependency, and MUST NOT execute anything from preset text.

### Key Entities

- **Duplicate origin**: the bundled preset a copy came from: its id, name, pack id and title, its
  content hashes, the pack's license statement, and whether the pack needs the unlock.
- **User preset** (PRE-012, extended): adds an optional duplicate origin and an optional last
  edit date; its content hashes always name the current text.
- **Edit check record**: the durable note naming the preset and candidate text being tried.
- **User-preset record** version 2.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-015-S1**: For every one of the 28 Included presets, the bundled file's bytes and hash,
  and the hash the index reports, are identical before duplicating, after duplicating, and after
  editing and saving the copy.
- **PRE-015-S2**: After an edit is saved, the copy's stored file differs from the original and its
  hash equals the hash of the saved text; the bundled preset still loads from the bundle, not from
  the copy.
- **PRE-015-S3**: Across duplicate, edit, rename, failed save, removal and migration, 100% of the
  store's file writes, moves and deletions are inside the user-preset directory, and a bundled
  file made read-only is never touched.
- **PRE-015-S4**: Locked presets are never stored by a duplicate attempt; after a revocation 0
  copies of pack presets are playable or editable; after the entitlement returns all of them are
  playable again, and none was deleted.
- **PRE-015-S5**: Every refused or failing edit leaves the stored preset byte-identical and
  playable; an app ending during an edit check never quarantines the preset.
- **PRE-015-S6**: The editor can be opened, edited, saved and cancelled at the largest
  accessibility text size, with every control labelled.
- **PRE-015-S7**: The editor opens the largest allowed preset (524,288 bytes) in under 2 seconds
  on the reference device D1 `{device}`.

## Assumptions

- "Bundled preset" means an Included preset or a pack preset from the archive. User presets can
  be edited but not duplicated (duplicating an import is not part of the roadmap row).
- The editor is a plain text editor: no syntax highlighting, no parameter controls (PRE-016) and
  no version history (PRE-017).
- The source pack's license statement comes from the app's own pack metadata (the same text as
  Settings › Licenses); nothing new is claimed about rights.
- Simulator and Mac results are not device evidence (Constitution X); device checks are tagged
  `{device}` and belong to the roadmap's final device phase.
- PRE-014 (export) must not export bundled content it has no right to redistribute
  (roadmap "Local formats and migration policy"). A copy's `duplicateOf` origin and its
  `rightsVerified = false` are recorded so that PRE-014 can recognize copies of bundled presets
  and apply its own rule; this feature exports nothing.
