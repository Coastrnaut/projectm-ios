# Feature Specification: SCN-005 Scene Tags

**Feature Branch**: `feature/scn-005` (spec directory `145-scn-005-scene-tags`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement SCN-005 (Scene tags) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Filter scenes by locally assigned labels and search text."
Acceptance, verbatim: "Tag changes update results and persist offline." Verification: schema round
trip, integration, simulator. P1, size S, depends on SCN-001 (integrated)."

Identifiers carry the roadmap ID: requirements `SCN-005-R1…`, success criteria `SCN-005-S1…`, tasks
`SCN-005-T01…`. Other features are cited by their own IDs: SCN-001 (scene document), SCN-003
(duplicate and rename), SCN-004 (scene folders), SHOW-001 (cue list), UIX-002 (scene switcher),
FILE-001 (scene archive), FILE-004 (import), FILE-005 (library backup), FILE-011 (erase), FR-070
(accessibility).

## Baseline: what exists today (audit of 2026-11-14, commit `cfc6f56f`)

The audit confirms the gap: scenes have no tags or labels.

| Area | Today |
|---|---|
| Saved scenes | SHOW-001's show: `Show/show.json` (cue list, format version 1) and `Show/Scenes/<SCENE-ID>.scene.json`. A scene is stored while a cue refers to it; saving drops scene files no cue refers to. |
| Organization | SCN-004 keeps logical folders in `show.json` as two optional keys (`folders`, `sceneFolders`); a show without them encodes to the bytes it had before; damaged entries are dropped with a warning (`ShowDecodeWarning`); names fold case, accents and width. Settings → Show → Scene Folders lists scenes per folder with swipe, context-menu and VoiceOver actions; folder edits announce on the announcer's library lane. |
| Switcher | UIX-002: flat list of the show's cues in show order; search folds case, accents and width and matches the label, the scene name and (SCN-004) the folder path. ⌘K opens it. Nothing is stored (UIX-002-R12). |
| Backup and import | FILE-005 re-encodes `show.json` through the show model (exact restore writes it back); merge restore and FILE-004 import decode the stored show, append cues and save it, so data already in the show is kept. FILE-001 archives hold one scene file only. |
| Erase | FILE-011's Show category removes the whole `Show` folder. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Where are tags kept? → A: In the show's index (`show.json`) as one optional key, `sceneTags`, mapping a scene ID to its list of tags, beside SCN-004's folder keys. Scene files are never changed, so tagging never alters a scene's canonical bytes, its ID or any cue. The format version stays 1; a show without tags encodes to exactly the bytes it had before.
- Q: Is the tag vocabulary stored or derived? → A: Derived: the set of tags is the union of the tags assigned to the show's scenes. A tag that no scene carries any more disappears. Rejected: a stored vocabulary (a second list to keep in step, with orphan tags to clean up and repair).
- Q: What makes a valid tag, and how many? → A: Trimmed text of 1 to 40 characters on one line (no control characters). At most 16 tags per scene and at most 256 distinct tags in a show. Two tags are the same when they are equal ignoring case, accents and width (the folding SCN-004 uses for folder names); a scene never carries the same tag twice. A tag keeps its display case.
- Q: Which display form wins when "live" and "Live" are typed? → A: When a tag is added that equals one already in the show (folded), the existing form is used, so the vocabulary has one spelling per tag. When stored data has several spellings (hand-edited files), each scene keeps its own; the vocabulary shows the spelling that sorts first.
- Q: How do several selected tags combine? → A: AND: a scene must carry every selected tag (each chip narrows the list, as tag filters usually do). The search text applies on top of the selected tags.
- Q: Where can the user filter? → A: In the UIX-002 scene switcher: a row of tag chips under the search field (shown when the show has tags), and the search text also matches tags. Selected chips are kept in memory only while the app runs, like the switcher's query (UIX-002-R12); no settings key is added. The Scene Folders screen shows each scene's tags but does not filter.
- Q: Where are tags edited? → A: A "Tags" sheet for one scene, opened from Settings → Show → Scene Folders (swipe action, context menu, VoiceOver action "Tags") and from a tag button on each switcher row. The sheet lists the scene's tags with Remove, a field with Add, and suggestions from the show's other tags. Changes save at once and never apply a scene.
- Q: Does a duplicated scene (SCN-003) keep its tags? → A: Yes, the copy gets its source's tags, as it gets its folder (SCN-004-R12).
- Q: What happens to tags when a scene leaves the show? → A: They are dropped with it at the next save (as its folder assignment and file are).
- Q: Do archives and backups carry tags? → A: The full backup carries them (it carries `show.json`) and exact restore keeps them. Merge restore and FILE-004 import keep the existing tags; incoming scenes arrive untagged. A single-scene archive (FILE-001) carries no tags (the scene file is unchanged by this row).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I tag scenes and filter by tag (Priority: P1) — MVP

A performer tags "Opening" and "Finale" with "Intro" and "Finale" with "Loud". In the switcher they
tap the "Intro" chip: only Opening and Finale are listed. They add "Loud" too: only Finale. They
remove "Intro" from Opening: the list updates at once. After relaunching the app, the tags and the
same filter results are still there, with no network.

**Why this priority**: It is the row's behaviour and acceptance.

**Independent Test**: Tag scenes through the show coordinator, filter the switcher entries by tags and
text, change a tag and check the results update, then reload the show from disk and check tags and
results are the same.

**Acceptance Scenarios**:

1. **Given** Opening and Finale tagged "Intro", **When** the "Intro" chip is selected, **Then** only their cues are listed.
2. **Given** that filter, **When** "Intro" is removed from Opening, **Then** only Finale's cue is listed.
3. **Given** tags assigned, **When** the show is reloaded from disk, **Then** every scene's tags and the filter results are the same.
4. **Given** a scene tagged "Ambient", **When** the user types "amb" in the switcher's search, **Then** its cue is listed.

---

### User Story 2 - Tag rules keep the list clean (Priority: P2)

Typing "intro " when "Intro" exists adds nothing new; a 41-character tag or a 17th tag is refused with
a message.

**Independent Test**: Unit tests for trimming, folding, deduplication, display form and limits.

**Acceptance Scenarios**:

1. **Given** a scene tagged "Intro", **When** "  INTRO " is added, **Then** it is refused as already present and nothing changes.
2. **Given** another scene tagged "Intro", **When** "intro" is added to a new scene, **Then** it is stored as "Intro".
3. **Given** a scene with 16 tags, **When** a 17th is added, **Then** it is refused ("A scene has at most 16 tags.").

---

### User Story 3 - Tags survive backup and older files (Priority: P2)

**Independent Test**: A backup round trip keeps every tag; a show file without `sceneTags` decodes with
no tags and re-encodes byte for byte; damaged tag data is dropped with a warning and the show loads.

**Acceptance Scenarios**:

1. **Given** a show with tags, **When** it is backed up and restored exactly, **Then** the tags are the same.
2. **Given** a show file written before this row, **When** it is read and written again, **Then** the bytes are identical.
3. **Given** a show file whose `sceneTags` has an unknown scene, an empty or overlong tag, duplicates or more than 16 tags, **When** it is read, **Then** the show loads, the bad entries are dropped and a warning reports how many.

### Edge Cases

- A selected chip whose tag no scene carries any more is dropped from the selection.
- With chips selected and no scene matching, the switcher says "No matching scenes" (as for a search).
- Two cues showing the same scene both match its tags (tags belong to the scene, not the cue).
- An unreadable scene keeps its tags and can still be tagged ("Scene missing" stays).
- A tag change that cannot be saved stays in effect for the session and the editor shows "The show could not be saved." (as other show edits).

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-005-R1**: Each scene the show's cues refer to can carry tags; tags are kept by scene ID and never change the scene ID, its file or any cue.
- **SCN-005-R2**: A tag is trimmed, 1 to 40 characters on one line; at most 16 tags per scene and 256 distinct tags per show; two tags are the same when equal ignoring case, accents and width; a scene carries each tag at most once; the display case is kept; adding a tag the show already has (folded) uses the existing spelling.
- **SCN-005-R3**: The tag vocabulary is derived from the assignments and sorted by folded text.
- **SCN-005-R4**: The user can add and remove a scene's tags; refused additions (invalid, already present, over a limit) change nothing and say why.
- **SCN-005-R5**: Tag changes never apply a scene, move the show's position or change cue order.
- **SCN-005-R6**: Tags are stored in the show index as an optional `sceneTags` key; format version stays 1; a show without tags encodes to the bytes it had before this row; encoding is deterministic (tags in a fixed order).
- **SCN-005-R7**: Damaged tag data never refuses the show: entries for scenes no cue shows, invalid tags, duplicates and tags over the limits are dropped with a warning that counts them.
- **SCN-005-R8**: The full backup and exact restore carry tags; merge restore and import keep existing tags; single-scene archives carry none.
- **SCN-005-R9**: Duplicate Scene copies the source's tags; a scene leaving the show loses its tags at the next save.
- **SCN-005-R10**: The switcher shows a row of tag chips (the vocabulary) when the show has tags; selected chips combine with AND and the search text applies on top; the search text also matches a scene's tags; selection is in memory only.
- **SCN-005-R11**: Each switcher row shows its scene's tags and VoiceOver reads ", tags Intro, Loud"; each chip has a label, the Selected trait when selected and a value with how many scenes carry it.
- **SCN-005-R12**: A Tags sheet for one scene, opened from the Scene Folders screen (swipe, context menu, VoiceOver action "Tags") and a tag button on each switcher row, lists its tags with Remove (button and VoiceOver action), a field with Add, and suggestions from the show's other tags. Scene Folders rows show their tags.
- **SCN-005-R13**: Tag additions, removals and refusals are announced through the app's announcer (library lane); a chip change announces the result count (search lane, as a query change).
- **SCN-005-R14**: No networking and no new settings keys; all data stays in the app's local show folder.

### Key Entities

- **Scene tag**: a short display string; identity is its folded form.
- **Scene tag map**: scene ID → ordered list of tags, part of the show.
- **Tag filter**: the switcher's selected tags (in memory), combined with AND.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-005-S1**: After a tag change the filtered results reflect it immediately, and after a reload from disk 100% of tags and the same results remain (acceptance test).
- **SCN-005-S2**: A show file without tags decodes with no tags and re-encodes byte for byte (fixture test).
- **SCN-005-S3**: 100% of over-limit, invalid and duplicate tags in the tests are refused (editing) or dropped with a warning (reading).
- **SCN-005-S4**: A backup round trip preserves every tag.
- **SCN-005-S5**: On the simulator a user adds a tag to a scene, selects its chip in the switcher and sees only the tagged scene, in a UI test under 30 seconds.

## Assumptions

- The show's scenes are the saved scenes this row tags (as SCN-004).
- Tag order on a scene is the order added; the vocabulary is sorted by folded text.
- Simulator and Mac results are not device evidence; this row needs no device-only check.
