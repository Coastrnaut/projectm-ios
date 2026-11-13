# Feature Specification: SCN-003 Scene Duplicate and Rename

**Feature Branch**: `feature/scn-003` (spec directory `074-scn-003-scene-duplicate-and-rename`)

**Created**: 2026-11-13

**Status**: Clarified 2026-11-13

**Input**: User description: "Implement SCN-003 (Scene duplicate and rename) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Duplicate scene under new ID and
rename without breaking references." Acceptance, verbatim: "Both scenes load independently and have
distinct IDs." P0, size S, depends on SCN-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SCN-003-R1…`, success criteria `SCN-003-S1…`, tasks `SCN-003-T01…`. Other
features are cited by their own IDs: SCN-001 (scene document, ADR-0028), SCN-002 (scene autosave),
SHOW-001 (cue list, ADR-0033), FILE-001 (scene archive), FILE-004 (import conflicts), FILE-010 (cache
cleanup), FILE-011 (local data erase), SCN-004 to SCN-006 (scene library), MED-001/MED-002 (stored
photo and video), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-13, commit `578cac5`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit confirms the gap:

| Needed | Today |
|---|---|
| A scene to duplicate or rename | SCN-001 defines the scene document (scene ID, name 1 to 120 characters, layers, parameters, bindings, modulation, assets). Where scenes are kept: SCN-002's one "current scene" (a fixed ID, autosaved) and SHOW-001's show, which stores each scene its cues use under its scene ID (`Show/Scenes/<ID>.scene.json`). There is no scene library (SCN-004 to SCN-006). |
| Duplicate | Nothing. SHOW-001's Add Current Scene makes a new scene from the shown look, not a copy of a stored scene. |
| Rename | SHOW-001 renames a cue's label; nothing renames a scene's own name. |
| References to a scene | Cues refer to a scene by its scene ID; FILE-001 archives carry the scene ID. Inside a scene, layers refer to scene-local asset keys, assets refer to the app's stored photo and video by store ID, and bindings and modulation connections refer to parameter IDs and generator IDs. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: Which scenes can the user duplicate and rename in this row, given there is no scene library yet? → A: The scenes the show stores (each cue's scene, from Settings → Show), plus the operations on the scene document itself so the library rows (SCN-004 to SCN-006) reuse them unchanged. SCN-002's current scene (one fixed ID, autosaved) is not duplicated or renamed: it is the live look, not a named scene. Rejected: building a scene library first (that is SCN-004's size M row); duplicating the current scene into a hidden store with no screen to reach it.
- Q: Should a duplicate copy the stored photo or video it uses, or share it? → A: Share it by store ID. The app keeps one photo and one video (MED-001, MED-002), so a copy of the media would be a second file no screen can reach; scenes already refer to media by store ID. Nothing counts references in a file: the set of referenced media is computed by reading every stored scene (`SCN-003-R9`), so it can never drift. FILE-010 (cleanup) must not delete media at all (it touches caches only) and FILE-011 (erase) must use this set before deleting media a scene still names. Replacing the stored photo or video (MED-001-R6) is unchanged: every scene that named the old one shows the existing "no longer stored" notice. Rejected: copying media (doubles storage, orphaned copies); a stored reference count (can drift from the files after a crash).
- Q: Where does the duplicate's cue go, and what are the copy's scene name and cue label? → A: A new cue right after the cue it was made from, so the variation sits next to its source; scene name "<name> copy" and cue label "<label> copy", each shortened to fit 120 and 80 characters. The show's position does not change and nothing is applied. Rejected: appending at the end (the copy lands far from its source in a long show); duplicating without a cue (the scene file would be removed at the next save, since SHOW-001 removes scenes no cue refers to).
- Q: When the user renames a scene that several cues show, what changes? → A: The scene's own name, once, for every cue that shows it (they all refer to the same scene ID); cue labels never change with it, and a cue rename never changes the scene name. The editor shows the scene name under a cue whose label differs. Rejected: renaming the scene also relabels cues (overwrites the operator's labels); copy-on-rename for shared scenes (a rename would silently break the link between cues).
- Q: How is a typed name stored: exactly as typed or trimmed, and what does "kept exactly" mean for the rest of the scene? → A: Trimmed of leading and trailing white space, then checked by the SCN-001 rule (1 to 120 characters, no control characters, which also excludes line breaks); an invalid name is refused. "Kept exactly" means the stored (canonical SCN-001) bytes of the copy, with its ID and name put back to the original's, equal the original's stored bytes; a rename likewise differs from the original only in the name. Rejected: storing untrimmed text (a name of only spaces around text would show oddly and differ from what the user sees); comparing decoded values only (would miss unknown content changes).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Duplicate a cue's scene to make a variation (Priority: P1)

A performer has a show whose cue 2 shows a scene they like. They want a variation of it for a later
part of the set without touching cue 2. In Settings → Show they choose Duplicate Scene on cue 2: a new
cue appears right after it showing a copy of the scene, under a new scene ID. Stepping through the
show, cue 2 and the new cue each show their own scene.

**Why this priority**: It is the row's behavior and its acceptance ("both scenes load independently
and have distinct IDs").

**Independent Test**: With a seeded five-cue show, Duplicate Scene on cue 2 adds cue 3 with a new
scene ID; both scene files decode and validate on their own; cue 2 still shows the original scene.

**Acceptance Scenarios**:

1. **Given** a show whose cue 2 shows scene A, **When** the performer chooses Duplicate Scene on cue 2,
   **Then** a new cue is inserted right after cue 2, it shows a new scene B whose ID differs from A's,
   and scene B holds the same look as A.
2. **Given** scenes A and B after a duplicate, **When** each is loaded from its file, **Then** each
   loads on its own (the other file may be missing) and both give the same live look.
3. **Given** cues that pointed at A before the duplicate, **When** the duplicate is done, **Then**
   they still point at A.

---

### User Story 2 - Rename a scene without breaking its cues (Priority: P1)

The performer gives the copy a meaningful name ("Build B"). The scene's name changes everywhere the
scene is used; its ID does not, so every cue that shows it still finds it.

**Why this priority**: It is the second half of the row's behavior ("rename without breaking
references").

**Independent Test**: Rename scene B; the scene file keeps its ID and file name, its name changes,
every cue that referred to it still resolves, and the cue labels do not change.

**Acceptance Scenarios**:

1. **Given** scene B shown by one or more cues, **When** the performer renames it to "Build B",
   **Then** the scene's stored name is "Build B", its ID is unchanged and every cue still shows it.
2. **Given** a name that is empty, only spaces, longer than 120 characters or contains a control
   character, **When** the performer confirms it, **Then** the rename is refused and the scene keeps
   its old name.
3. **Given** a cue label and a scene name, **When** either is renamed, **Then** the other does not
   change.

---

### User Story 3 - Later scene features reuse the same rules (Priority: P2)

The scene library (SCN-004 to SCN-006) will duplicate and rename scenes too. The rules for a new ID, a
valid name and what is kept live with the scene format, so every place that duplicates or renames
gives the same result.

**Why this priority**: It keeps later rows consistent; users see it only through them.

**Independent Test**: Duplicating any document from a fixed-seed set of random scenes keeps
everything but the ID and name exactly, and renaming keeps everything but the name.

### Edge Cases

- **Scene missing or unreadable**: Duplicate Scene and Rename Scene are refused for a cue whose scene
  cannot be read ("Scene missing"); a message says why. Nothing is written.
- **Show full (256 cues)**: Duplicate Scene is refused with the show's limit message; no scene file is
  written.
- **Name of the copy**: the copy is named "<name> copy" (shortened so it stays within 120
  characters); the new cue's label is "<label> copy" (within 80 characters).
- **Shared scene**: when several cues show the same scene, renaming it renames it for all of them;
  duplicating from one cue leaves the others on the original.
- **Saving fails**: the show and every scene file are written whole; a failure leaves the previous
  files intact and the editor says the show could not be saved.
- **Stored photo or video**: the copy refers to the same stored photo or video as the original (no
  second copy of the media). If that media is replaced or removed later, both scenes show the
  "photo or video no longer stored" notice, as one scene does today.
- **Unknown content** (fields from a newer app version) is kept in the copy and through a rename.
- **Deleting the original's cues**: the original scene file is removed (SHOW-001 removes scenes no
  cue refers to); the copy is unaffected.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-003-R1**: Duplicating a scene MUST produce a scene with a new scene ID different from the
  original's and a valid name; everything else (layers and their instance IDs, composite settings,
  parameters, bindings, modulation generators and connections, assets, embedded text and graph
  documents, unknown content) MUST be kept exactly, so that the copy's stored form equals the
  original's with only the ID and name replaced.
- **SCN-003-R2**: Renaming a scene MUST change only its name; its ID and everything else MUST be kept
  exactly.
- **SCN-003-R3**: A scene name MUST be checked before it is stored: leading and trailing white space
  is removed, and the result must be 1 to 120 characters with no control characters (the SCN-001
  rule). An invalid name MUST be refused without changing anything.
- **SCN-003-R4**: Duplicate and rename MUST NOT break references: cues refer to scenes by scene ID, so
  a rename keeps every cue's reference and a duplicate leaves every existing cue on the original; the
  copy's layers keep referring to its own asset keys; asset store IDs, parameter IDs and generator IDs
  are copied unchanged.
- **SCN-003-R5**: Both scenes MUST load independently: each stored file decodes and validates without
  the other, and the two give equal live states.
- **SCN-003-R6**: The show editor (Settings → Show) MUST offer, on each cue, Duplicate Scene (store a
  copy under a new ID and insert a cue for it right after the cue) and Rename Scene (rename the cue's
  scene), next to the existing Rename (cue label). Neither changes the output or the show's position.
- **SCN-003-R7**: The editor MUST show a cue's scene name when it differs from the cue's label, and
  VoiceOver MUST read it in the cue's value (FR-070).
- **SCN-003-R8**: Every file written by duplicate or rename MUST be written whole (never half
  written); the copy's scene file MUST be stored before the show refers to it.
- **SCN-003-R9**: Stored photo and video MUST be shared by reference, not copied. The app MUST be able
  to list every stored photo and video ID referred to by any stored scene (computed from the stored
  scenes, never a stored count), so that any later cleanup (FILE-010) or erase (FILE-011) can avoid
  orphaning a scene's media. Deleting a scene (its last cue removed) MUST NOT delete media another
  scene still refers to.
- **SCN-003-R10**: The feature stays on the device: no network use; it stores nothing new beyond
  scene names and copies of scenes the user made.

### Key Entities

- **Scene document** (SCN-001): scene ID, name, layers, parameters, bindings, modulation, assets.
- **Cue** (SHOW-001): cue ID, scene ID, label.
- **Scene reference**: anything that names a scene by its ID (cues today, archives, the library later).
- **Media reference**: a scene asset that names the app's stored photo or video by store ID.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-003-S1** (the row's acceptance): after a duplicate, two scene files exist with distinct IDs;
  each loads on its own and gives a live state equal to the other's; the original's cues still find
  their scene (100%).
- **SCN-003-S2**: after a rename, the scene's ID, file and every cue reference are unchanged and only
  the name differs (100%).
- **SCN-003-S3**: for a fixed-seed set of at least 200 random scenes, duplicate and rename keep every
  part but the ID and name exactly (stored forms equal after the ID and name are put back), in under
  1 s.
- **SCN-003-S4**: every name in a table of valid and invalid names is accepted or refused as
  specified.
- **SCN-003-S5**: in the app (simulator), duplicating cue 2's scene and renaming the copy, then
  stepping through the cues, shows the original and the copy as separate scenes with distinct IDs.
- **SCN-003-S6**: unit tests run in at most 10 s each and each package suite in under 1 minute; the
  UI test in under 30 s (owner rule 7).

## Assumptions

- No scene library exists yet; this row applies duplicate and rename to the scenes the show stores,
  and to the scene document itself so the library rows reuse it.
- SCN-002's current scene (one fixed ID) is not duplicated or renamed in this row: it is not a named
  user scene.
- Importing an archive whose scene ID already exists is FILE-004's job; this row only makes new IDs.
- The app stores one photo and one video at a time (MED-001, MED-002); replacing them is unchanged.
