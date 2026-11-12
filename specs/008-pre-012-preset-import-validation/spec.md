# Feature Specification: PRE-012 Preset import validation

**Feature Branch**: `feature/pre-012` (spec directory `008-pre-012-preset-import-validation`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement PRE-012 (Preset import validation) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Validate local preset syntax, size, dependencies and license metadata." Acceptance, verbatim: "Invalid file is quarantined and cannot crash renderer." Dependencies: none. Honor the repository constitution."

**Roadmap row**: PRE-012, priority P0, effort L, no dependencies
(`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PRE table). Later rows build on it and are out of scope
here: PRE-013 (bulk import), PRE-014 (export), PRE-015 (duplication), PRE-016 (overrides),
PRE-017 (restore points), PRE-018 (integrity scanner), SHD-011, PERF-014, QA-005.

**ID convention**: requirements are `PRE-012-R1…`, success criteria `PRE-012-S1…`, tasks
`PRE-012-T01…`. Identifiers such as FR-065 cite feature 001
(`specs/001-ios-projectm-visualizer/spec.md`); FR-101 and above cite feature 002
(`specs/002-preset-library-unlock/spec.md`); `PRE-007-…` cites
`specs/005-pre-007-preset-collections/spec.md`; `AUD-001-…` cites
`specs/003-aud-001-import-drm-free-audio-files/spec.md`.

## What already exists (audit of HEAD, 2026-11-12)

The audit read the code, its tests and the pinned engine source at commit `e834535`.

| Area | What HEAD does | Evidence | Gap |
|---|---|---|---|
| Preset sources | Only presets built into the app: 28 Included files and the packs' archive. | `PresetLibrary.swift`, `PresetArchive.swift`, `scripts/build_preset_index.py` | The user cannot add a preset. |
| Build-time checks | The build drops duplicate contents, contents on the takedown list (`PresetBlocklist.json`) and 94 presets that the pre-release load sweep found broken. | `build_preset_index.py`, `PresetExclusions.txt`, `docs/test-reports/preset-library.md` | Nothing checks a file at run time. |
| Engine load failure | A preset the engine rejects leaves the previous preset on screen; the app shows "Preset could not be loaded" and leaves the preset out for the session (FR-045, FR-118). | `PMBridge.mm`, `PresetCoordinator.select` | Nothing is remembered across launches; nothing checks a preset before it reaches the visible picture. |
| Background engine | A second engine on its own drawing context renders upcoming presets off screen (SC-104). | `PresetPrewarmer.swift` | Used only for warm-up; its failures are ignored. |
| File import | Audio files: copied into app storage, hashed, recorded in a versioned index (AUD-001). | `AudioLibrary.swift` | No preset import. |
| User-made lists | Favorites and collections refer to presets by id (FR-044, PRE-007). | `FavoritesStore.swift`, `PresetCollectionStore.swift` | They can only name built-in presets. |

### How the pinned engine behaves on bad input (audit of `Vendor/projectM` at `c88894e`)

| Input | Engine behavior | Contained today? |
|---|---|---|
| File over 1 MiB, a NUL byte anywhere, or no `key=value` line at all | The file parser refuses it; the load fails with a message. | Yes (typed failure). |
| Equation code (per-frame, per-pixel, init, custom wave and shape code) that does not compile | Load fails with a message such as "Could not compile per-frame code". All 94 load-sweep exclusions were of this kind; none crashed. | Yes (typed failure). |
| Warp or composite shader that is empty, lacks `shader_body`, lacks braces, or does not translate or compile | The engine logs an error, drops that shader and loads the preset without it. | Yes (degraded picture, no failure). |
| A texture named by a shader that is not found | A 1 × 1 placeholder texture is used; the preset loads. | Yes (degraded picture). |
| Code numbering with a gap (`per_frame_1`, `per_frame_3`) | Lines after the gap are silently ignored. 11 built-in presets have such gaps. | Yes. |
| Equation loops | Each `loop`/`while` is capped at 1,048,576 iterations, but loops nest (built-in presets nest up to 4 deep), so a hostile preset can run effectively forever, during load (init code) or in every frame. | **No.** A hang on the visible renderer freezes the app. |
| Very deep expression nesting or very long operator chains | The equation compiler, the shader translator and the code that runs equations recurse; depth is not limited. | **No.** A stack overflow is a native crash. |
| Anything else that is a defect in the engine or the graphics translator | Undefined. | **No.** |

The feature therefore needs three layers: static checks that keep input inside the envelope of
presets the engine is known to handle; a trial on an engine that is not the visible one, with a
time limit; and a persistent record so a preset that killed or hung the app is not tried again.

## Clarifications

### Session 2026-11-12

Answered under the standing delegation (recommended option first; no owner question was needed).
Measurements are of the 14,604 `.milk` files built into the app (the four packs and Included),
taken with a script on 2026-11-12.

- Q: What are the static limits, and how far above real presets are they? → A: File size at most 524,288 bytes (512 KiB): the largest built-in preset is 168,391 bytes, the 99.9th percentile is 36,652, and the engine itself refuses files over 1 MiB. A line at most 8,192 bytes (largest built-in: 1,525). At most 20,000 lines (largest: 3,220). One code block at most 131,072 bytes (largest: 31,999). One statement at most 8,192 bytes after comments are removed (largest equation statement: 4,891; largest shader statement: 1,311). Brackets `(`, `[`, `{` nested at most 64 deep (deepest: 21). The statement and nesting limits exist because the engine's equation compiler, equation runner and shader translator recurse without a depth limit; they bound how deep that recursion can go. Every limit accepts the whole built-in corpus (S7). (R3, R8, R10)
- Q: Is a texture that the app does not have a reason to quarantine, or a warning? → A: A warning. The engine substitutes a 1 × 1 placeholder and the preset still draws; 109 distinct texture names appear in the built-in corpus and several are not in the bundled texture pack, yet those presets play. Quarantining would refuse presets that work. The missing names are recorded on the preset so PRE-018 (integrity scanner) can offer a relink later. The same reasoning makes a numbering gap (11 built-in presets), a repeated key (764 occurrences in the corpus) and a line the engine ignores warnings. A declared warp or composite shader with unbalanced braces or parentheses, or without `shader_body`, is quarantined although the engine would only drop the shader: it is the signature of a truncated file, and only 2 of 14,604 built-in presets would be affected. (R9, R10, R11)
- Q: What license metadata is recorded when Milkdrop presets almost never carry any? → A: Four facts, none invented. Origin: "supplied by the user" (the only value this feature writes). Rights verified: always no. Author: the text before the first " - " in the file name, stored as a guess and shown as "from the file name"; empty when the name has no such part. Lines found in the file: up to 5 lines, each cut to 200 characters, that contain the words license, licence, copyright, "public domain", "creative commons", a "CC-BY"/"CC0" tag or the © sign, kept verbatim. No field for a license the user states is added now: nothing in this feature would use it, and PRE-014 can add it with its own export rule. Later export features must treat "supplied by the user, rights not verified" as the user's own file and must never treat it as bundled content. (R12, R26)
- Q: What happens to a file whose content the app already has? → A: It is refused and nothing is stored. Same content as an imported preset: the message names that preset. Same content as a quarantined file: the message gives its reason; deleting it from Quarantine allows a new attempt. Same content as a built-in preset, in any pack and whether locked or not: the message names the built-in preset and its pack. Content is compared with the same content hash the built-in index and the takedown list use, so the comparison needs no built-in file to be read. Refusing copies of built-in presets keeps bundled content out of user storage, so a later export can never carry it and import can never act as a way around the purchase. (R5, R6, R23)
- Q: What exactly can and cannot be contained, and with what limits? → A: Contained: every failure the engine reports (caught in the trial, before the preset is playable); a preset that never finishes (the trial has a 10 second limit; it loads the preset and draws 30 frames with a test tone on an engine and drawing context separate from the visible one, on a worker with a stack no larger than the visible renderer's, so recursion that survives the trial survives on screen); a later failure on the visible renderer (previous preset keeps playing, preset quarantined). Not contained in-process: a native crash inside the engine or graphics translator during the trial ends the app once; the durable trial record then quarantines the preset at the next launch, so it cannot loop. A trial that hangs cannot be stopped: its worker is abandoned and keeps running until the app closes, at most one such worker exists, and while it exists later imports wait unchecked. A preset is "proven" after 3 seconds on the visible renderer; the app ending inside those 3 seconds quarantines it, which also catches a user who force-quits in that window (accepted: delete from Quarantine and import again). A trial interrupted by the app going to the background is "not checked yet", not a failure. (R14-R21)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Import a preset of my own and play it (Priority: P1)

A person has a Milkdrop preset file (`.milk`) in Files. In the preset browser they open "My
Presets", choose "Import Preset…", and pick the file. The app copies it into its own storage,
checks it, and tries it out of sight. When the check passes, the preset appears under My Presets
with the name and author taken from its file name. Tapping it plays it; Next, Previous and Random
then stay inside My Presets, exactly as with Favorites or a folder. The preset is still there, and
still plays, after the original file is deleted and the app is relaunched.

**Why this priority**: Without a successful import there is nothing to validate; it is the
observable behavior of the roadmap row.

**Independent Test**: Import a small valid preset, see it listed, play it, step with Next and
Previous, delete the original, relaunch, and play it again.

**Acceptance Scenarios**:

1. **Given** a valid preset file, **When** the user imports it, **Then** it is listed under My
   Presets, the user is told it was added, and it plays when tapped.
2. **Given** an imported preset is playing from My Presets, **When** the user presses Next,
   Previous or Random, **Then** only presets of My Presets are played, wrapping at both ends.
3. **Given** an imported preset, **When** the original file is moved or deleted and the app is
   relaunched, **Then** the preset is still listed and still plays.
4. **Given** the user has not bought the full library, **When** they import a preset, **Then**
   every pack stays locked, and the imported preset plays without a purchase.
5. **Given** an imported preset, **When** the user stars it or adds it to a collection, **Then**
   it appears in Favorites or in that collection like any other preset.
6. **Given** an imported preset, **When** the user removes it and confirms, **Then** it leaves My
   Presets and its stored copy is deleted; built-in presets are untouched.

---

### User Story 2 - A bad file is quarantined with a reason (Priority: P1)

The person picks a file that is not a usable preset: a renamed image, an empty file, a file
truncated in the middle, a file with absurdly long lines, or a preset whose equations the engine
cannot compile. The app does not play it. It tells the user, in one sentence, what is wrong, and
lists the file under Quarantine with that reason. The picture on screen keeps running the whole
time. From Quarantine the user can delete the file.

**Why this priority**: This is the acceptance check: "Invalid file is quarantined and cannot crash
renderer."

**Independent Test**: Import each invalid fixture; check that each ends in Quarantine with the
expected reason, that none appears in any playable list, and that the current preset keeps
drawing.

**Acceptance Scenarios**:

1. **Given** a `.milk` file that fails a static check, **When** the user imports it, **Then** it is
   not playable, a message names the reason, and it is listed in Quarantine with that reason.
2. **Given** a file that passes the static checks but that the engine rejects, **When** the user
   imports it, **Then** the engine failure is caught during the off-screen trial, the preset is
   quarantined with the reason "the visualizer could not load it", and the visible picture never
   changes.
3. **Given** a preset whose trial does not finish within the time limit, **When** the limit
   passes, **Then** it is quarantined as "took too long" and the app stays responsive.
4. **Given** a quarantined file, **When** the user opens any preset list, Favorites, a collection,
   search or uses Next, Previous or Random, **Then** the file is never offered or played.
5. **Given** a quarantined file, **When** the user deletes it from Quarantine, **Then** its record
   and stored copy are gone.
6. **Given** a file the app will not keep at all (too large, not a `.milk` file, unreadable, a
   copy of a built-in preset, a copy of something already imported, or content on the takedown
   list), **When** the user picks it, **Then** nothing is stored, and a message says why.

---

### User Story 3 - The app survives a preset that kills it (Priority: P1)

A hostile or broken preset makes the app crash or freeze while it is being tried. When the person
opens the app again, it starts normally with a built-in or earlier preset. The offending file is
in Quarantine with the reason that the app closed while checking it. The app does not try it again
by itself.

**Why this priority**: Without it, "cannot crash renderer" would hold only for failures the engine
reports politely, and one bad file could make the app unusable at every launch.

**Independent Test**: Simulate the app dying during a trial (the "trial in progress" note is left
behind), relaunch, and check the preset is quarantined, is not retried, and the app plays another
preset.

**Acceptance Scenarios**:

1. **Given** the app ended while a preset's trial was in progress, **When** it starts again,
   **Then** that preset is quarantined with the reason "the app closed while checking it" and no
   trial of it starts.
2. **Given** a preset that passed its trial is shown on screen for the first time, **When** the app
   ends within the first seconds of showing it, **Then** at the next start that preset is
   quarantined and the app starts with a different preset.
3. **Given** a preset that passed its trial later fails to load on the visible renderer, **When**
   that happens, **Then** the previous preset keeps playing, the user is told, and the preset is
   quarantined.
4. **Given** a quarantined preset was the last one playing, **When** the app starts, **Then** it
   starts with another playable preset.

---

### User Story 4 - See what the app knows about an imported preset (Priority: P2)

For each imported preset the person can open an information view: the original file name, the
size, when it was imported, the author guessed from the file name, any license or copyright line
found in the file, the statement that the app has not verified any rights to it, and warnings
found during validation (for example textures the preset names that the app does not have).

**Why this priority**: The roadmap row asks for dependency and license metadata validation; the
result must be visible to be of use, and later export features rely on what is recorded here.

**Independent Test**: Import a preset that names an unknown texture and carries a license comment;
open its information and find both.

**Acceptance Scenarios**:

1. **Given** a preset that names a texture the app does not have, **When** it is imported,
   **Then** it is accepted, and its information lists the missing texture as a warning.
2. **Given** a preset with a comment line stating a license, **When** it is imported, **Then** its
   information shows that line verbatim as "found in the file".
3. **Given** a preset with no license text, **When** it is imported, **Then** its information says
   that no license information was found; no license is ever invented.

### Edge Cases

- The picked file has no `.milk` extension, is a folder, is empty, or cannot be read: refused,
  nothing stored.
- The file name contains path separators, `..`, control characters, emoji or right-to-left text:
  the name is only ever shown as text and never used as a storage path.
- The file uses CRLF line endings, a byte-order mark, or bytes that are not valid UTF-8 (37
  built-in presets are Latin-1): accepted; the stored copy is byte-identical to the original.
- The same content is imported twice, or under another name: the second import is refused with the
  name of the existing entry. Content already in Quarantine is refused with its reason; deleting
  it from Quarantine allows a new attempt.
- The content equals a built-in preset (any pack, locked or not): refused; the message names the
  built-in preset. Nothing is unlocked.
- Storage is full or the save fails: nothing changes, the user is told.
- The saved index was written by a newer app version: user presets are unavailable, nothing is
  modified, the user is told to update. An unreadable index is set aside and the library is
  rebuilt empty; stored files are not deleted by that.
- No off-screen trial is possible right now (the renderer is not running, the app is in the
  background, or an earlier trial is still stuck): the preset waits as "not checked yet", is not
  playable, and is checked at the next opportunity.
- The app goes to the background during a trial: the trial is abandoned as "not checked yet", not
  as a failure.
- The user force-quits the app during a trial: indistinguishable from a crash; the preset is
  quarantined. Deleting it from Quarantine and importing it again is the way to retry.
- A user preset is deleted while it is playing: it keeps playing until the next switch.
- The limits on the number of user presets or quarantined files are reached: further imports are
  refused with that reason.
- Very large text size, VoiceOver, Reduce Motion: every new screen works with them.

## Requirements *(mandatory)*

### Functional Requirements

**Import**

- **PRE-012-R1**: The preset browser MUST offer a "My Presets" entry and, inside it, an "Import
  Preset…" action that opens the system file picker for one file.
- **PRE-012-R2**: An import MUST copy the picked file into storage owned by the app before
  validating it; the app MUST NOT depend on the original location afterwards and MUST NOT store a
  reference to it.
- **PRE-012-R3**: The picker result MUST be refused, with nothing stored, when the item is not a
  regular file, has no `.milk` extension, is empty, cannot be read, or is larger than 524,288
  bytes. Reading MUST stop at that limit.
- **PRE-012-R4**: Stored copies MUST be named by a hash of their content, never by any part of the
  original file name. The original name is kept only as display text, cleaned of control
  characters and path separators and limited in length.
- **PRE-012-R5**: Content identical to a built-in preset, to an already imported preset, or to a
  quarantined file MUST be refused with a message naming the existing entry; nothing is stored.
- **PRE-012-R6**: Content whose hash is on the app's takedown list (`PresetBlocklist.json`) MUST be
  refused; nothing is stored.

**Static validation (before any engine sees the file)**

- **PRE-012-R7**: Validation MUST be bounded: it reads at most the size limit, runs in time
  proportional to the file size, uses no recursion that grows with the input, and executes nothing
  from the file.
- **PRE-012-R8**: Size and text checks. A file MUST be quarantined when it contains a NUL byte or
  another control character other than tab, line feed and carriage return; when a line is longer
  than 8,192 bytes; or when it has more than 20,000 lines. CRLF, CR and LF line
  endings, a UTF-8 byte-order mark and non-UTF-8 bytes above 0x7F are accepted.
- **PRE-012-R9**: Structure checks. A file MUST be quarantined when it has no `[preset00]` section
  header before its first setting, or when it has no setting at all. Lines the engine ignores
  (comments, text without `=`) and repeated keys are tolerated and reported as warnings.
- **PRE-012-R10**: Code checks, per code block (per-frame, per-frame init, per-pixel, warp shader,
  composite shader, and each custom wave's and shape's init, per-frame and per-point code). A file
  MUST be quarantined when a block exceeds 131,072 bytes, when a single statement exceeds
  8,192 bytes, when brackets nest deeper than 64, when an equation block
  has unbalanced parentheses, or when a declared warp or composite shader has unbalanced braces or
  parentheses or no `shader_body`. A gap in a block's line numbering is a warning that names the
  block (the engine ignores the lines after the gap).
- **PRE-012-R11**: Dependencies. Texture names used by the warp and composite shaders MUST be
  compared with the names the engine provides itself and the textures shipped with the app. Names
  that are neither MUST be recorded as warnings on the imported preset; they do not block the
  import.
- **PRE-012-R12**: License metadata. The app MUST record, per imported preset: that the file was
  supplied by the user; that the app has verified no rights to it; the author guessed from the
  file name, marked as a guess; and up to 5 lines from the file (each cut to 200 characters) that mention a
  license or copyright, verbatim. It MUST NOT assign or imply a license that the file does not
  state.
- **PRE-012-R13**: Each quarantine reason MUST be specific and shown to the user in plain words,
  with the limit that was exceeded where there is one.

**Trial and containment**

- **PRE-012-R14**: A preset that passed static validation MUST NOT be playable until it was loaded
  and drawn for several frames, with audio input, by an engine that is not the one drawing the
  visible picture. The visible picture MUST be unaffected by the trial's outcome.
- **PRE-012-R15**: The trial MUST have a time limit of 10 seconds. A trial that does not finish in time MUST end
  with the preset quarantined, and the app MUST stay responsive. At most one trial runs at a time,
  and at most one abandoned trial may exist; while one exists, later imports wait as "not checked
  yet".
- **PRE-012-R16**: A trial MUST end in exactly one of: passed, failed with the engine's message,
  timed out, or not possible now. Failed and timed out quarantine the preset. "Not possible now"
  leaves it waiting and unplayable.
- **PRE-012-R17**: Before a trial starts, the app MUST durably record which preset is on trial,
  and clear that record when the trial ends. At launch, a preset still recorded as on trial MUST
  be quarantined without being tried again.
- **PRE-012-R18**: The first time a preset that passed its trial is shown on the visible renderer,
  the same durable record MUST be kept until the preset has been drawn for a proving
  period of 3 seconds. If the app ends inside that period, the preset MUST be quarantined at the next launch.
  Once proven, the preset is loaded without the record.
- **PRE-012-R19**: If a user preset fails to load on the visible renderer, the previous preset
  MUST keep playing, the user MUST be told, and the preset MUST be quarantined.
- **PRE-012-R20**: A quarantined file MUST never be passed to the visible renderer, and MUST NOT
  appear in My Presets, All, search, Favorites, a collection or any Next/Previous/Random scope. A
  quarantined file leaves quarantine only by being deleted.
- **PRE-012-R21**: The limits of containment MUST be documented: a native crash inside the engine
  during a trial ends the app once; a trial that hangs leaves one stuck background task until the
  app is closed.

**Library, scope and separation from built-in content**

- **PRE-012-R22**: User presets MUST form their own scope, "My Presets", for Next, Previous and
  Random, listed alphabetically; the scope MUST persist like the other scopes. They MAY be starred
  and added to collections; they MUST be found by search. They are not part of "All presets A-Z",
  whose content and count stay the built-in library.
- **PRE-012-R23**: Importing MUST NOT change the purchase state, the lock state of any pack, any
  built-in file, or the saved collections format. User presets never need a purchase.
- **PRE-012-R24**: The user MUST be able to remove an imported preset (with confirmation) and to
  delete a quarantined file; both delete the stored copy. Favorites and collections entries that
  name a removed preset simply stop being shown.
- **PRE-012-R25**: Every change to the user-preset library MUST be saved before it is shown, as
  one versioned record replaced atomically. A failed save MUST leave the record and the stored
  files as they were and MUST be reported. A record from a newer app version MUST NOT be
  interpreted or modified; an unreadable record MUST be set aside, not deleted.
- **PRE-012-R26**: Each user preset MUST have a permanent id that does not depend on its name, and
  the record MUST keep the content hash, sizes, import date, validation warnings and license
  metadata, so later features (export, duplication, integrity scan) can rely on them.
- **PRE-012-R27**: At most 1,000 user presets and 200 quarantined files are kept; an import that
  would exceed either is refused with that reason.

**Interface, accessibility, privacy**

- **PRE-012-R28**: The result of every import MUST be shown and announced to assistive
  technology: added, added with warnings, waiting to be checked, quarantined with the reason, or
  refused with the reason. While an import is being checked the screen MUST show progress.
- **PRE-012-R29**: My Presets, the information view and Quarantine MUST have accessible labels,
  work at the largest text sizes, and require no gesture that has no alternative.
- **PRE-012-R30**: Amends FR-065 (as amended by FR-123, AUD-001-R22 and PRE-007-R17): on-device
  persistence additionally includes the preset files the user imports, including quarantined
  ones, and their record (display name, sizes, hashes, import date, validation result). They stay
  on the device, are never sent anywhere, and are deleted when the user removes them or deletes
  the app. The privacy policy MUST say so.
- **PRE-012-R31**: The feature MUST use only public system interfaces, no networking, no new
  entitlement and no new third-party dependency, and MUST NOT execute anything from an imported
  file other than handing the preset text to the visualizer engine.

### Key Entities

- **User preset**: one imported file. Permanent id, display name, author guess, original file
  name (display only), content hashes, size, import date, state (waiting for check, playable,
  quarantined), whether it has been proven on screen, warnings, license metadata.
- **Quarantine reason**: why a file is not playable; one of a fixed list (static check that
  failed, engine refused it, took too long, app closed during the check, app closed while first
  showing it, failed on the visible renderer).
- **Import warning**: a non-blocking finding (missing texture, numbering gap, ignored line,
  repeated key, shader the engine will likely drop).
- **License metadata**: origin (supplied by the user), rights verified (always no), lines found in
  the file, author guess.
- **Trial record**: the durable note naming the one preset being tried or proven.
- **User-preset library record**: versioned document listing every user preset and quarantined
  file.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-012-S1**: Every one of the invalid fixture files (empty, binary, oversize, truncated in a
  shader, a line of a million characters, deeply nested brackets, missing header, unbalanced
  equation, takedown-listed, duplicate of a built-in preset, hostile file names) ends refused or
  quarantined with the expected reason, and none becomes playable.
- **PRE-012-S2**: In a seeded sweep of at least 500 corrupted variants of a valid preset, no
  variant crashes or stalls validation (each finishes within 1 second), every refusal leaves the
  stored library byte-for-byte unchanged, and every quarantined variant stays out of the playable
  list.
- **PRE-012-S3**: With the real engine on the simulator, presets that pass the static checks but
  that the engine cannot load are quarantined, the app keeps running, and the visible renderer
  keeps drawing the preset it was drawing.
- **PRE-012-S4**: After a simulated death of the app during a trial or during the proving period,
  the next start quarantines exactly that preset, starts no trial of it, and plays another preset.
- **PRE-012-S5**: A valid imported preset is playable within 5 seconds of being picked on the
  simulator, survives deletion of the original and a relaunch, and Next/Previous/Random stay
  inside My Presets.
- **PRE-012-S6**: Importing changes neither the purchase state nor any built-in file, and the
  existing collections file format and its version-1 fixture are unchanged.
- **PRE-012-S7**: All static limits accept every preset built into the app: validating the whole
  built-in corpus quarantines nothing for exceeding a limit.

## Assumptions

- One file per import; folders, archives and multi-selection are PRE-013.
- Only `.milk` files are importable. The four built-in `.prjm` files are not a user format.
- Limits are set from measurements of the built-in corpus (14,604 `.milk` files) with headroom;
  the numbers and measurements are in Clarifications.
- Simulator and Mac results are not device evidence (Constitution X); device checks are tagged
  `{device}` and belong to the roadmap's final device phase.
- Editing, duplicating, exporting and re-scanning user presets are later roadmap rows. This
  feature records what they need (permanent ids, hashes, license metadata) and no more.
- The user who imports a file is responsible for having the right to use it; the app states that
  it verified nothing.
