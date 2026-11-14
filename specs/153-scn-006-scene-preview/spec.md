# Feature Specification: SCN-006 Scene Preview Image

**Feature Branch**: `feature/scn-006` (spec directory `153-scn-006-scene-preview`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement SCN-006 (Scene preview image) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Capture representative image for
scene browser." Acceptance, verbatim: "Preview corresponds to saved scene and invalidates after edit."
P1, size M, depends on SCN-001 (integrated)."

Identifiers carry the roadmap ID: requirements `SCN-006-R1…`, success criteria `SCN-006-S1…`, tasks
`SCN-006-T01…`. Other features are cited by their own IDs: SCN-001 (scene document), SCN-003
(duplicate and rename), SCN-004 (scene folders), SCN-005 (scene tags), SHOW-001 (cue list), UIX-002
(scene switcher), PRE-001 and PRE-002 (preset thumbnail cache and invalidation), REC-001 (Save Frame),
FILE-005 (library backup), FILE-009 and FILE-010 (storage usage, Clear Caches), FILE-011 (erase),
ACC-002 (Reduce flashing), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-14, commit `1fe5f95c`)

The audit confirms the gap: no scene has a picture anywhere.

| Area | Today |
|---|---|
| Saved scenes | SHOW-001: `Show/show.json` and `Show/Scenes/<SCENE-ID>.scene.json` (canonical SCN-001 bytes). Add Current Scene stores a new scene; SCN-003 Rename Scene rewrites the file; removing the last cue of a scene deletes its file at the next save. |
| Where scenes are listed | UIX-002 switcher rows (label, subtitle, tags), SCN-004 Scene Folders rows (icon, name, tags). |
| Preset thumbnails | PRE-001/PRE-002 (`PresetLibrary/Thumbnails`): content-hash keys, a versioned JSON index in `Library/Caches/PresetThumbnails` with open-time repair, invalidation by preset ID, launch collection (`retainOnly`), PNG files, excluded from backup, counted and cleared as Caches (FILE-009/010). |
| Frame grab | REC-001 `FrameCaptureSource.captureFrame`: the shown visual's next presented frame after its flash limiting (ACC-002, FX-019), one request at a time, 1 s timeout. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What is the preview? → A: A still of the live output, captured when a scene is saved (Settings → Show → Add Current Scene: at once, since the output already shows it) or applied through the cue path (Next, Previous, Go to Cue, the switcher, Scene Folders' Go to Cue) after a 1 s settle. It reuses REC-001's frame grab, so Reduce flashing and the flash guard are already applied to the picture. Rejected: rendering scenes offscreen (a second engine, shader compiles, media and audio that differ from what the user saw).
- Q: How is a preview tied to the saved scene? → A: By the scene ID plus the SHA-256 of the scene file's bytes. Any change to the file (an edit, SCN-003 rename, a restore) gives a new hash, so the old preview no longer matches; it is removed with its file. A rename therefore also invalidates (the preview always matches the exact saved file).
- Q: What is shown when there is no valid preview? → A: A placeholder (the row's existing icon look) until the scene is next applied or saved. No offscreen re-render.
- Q: Which captures are kept? → A: Only a capture whose scene is still the applied one, whose file hash is unchanged and whose live look has not changed since the apply (the user did not edit settings during the settle), with the output live (not blacked out, not paused). A later apply cancels a pending capture. A user Save Frame in progress is never disturbed (the preview capture is skipped).
- Q: Where are previews stored? → A: Small PNG files (192 × 108, 16:9, centre crop) with a versioned index in `Library/Caches/ScenePreviews`: rebuildable, excluded from backup, counted in Storage's Caches and removed by Clear Caches. FILE-005 backups and FILE-001 archives do not carry them; FILE-011's erase of Caches covers them.
- Q: When are previews pruned? → A: When a scene's file changes (its previews for other hashes go), when a scene leaves the show (all of its previews go), and at launch (anything not matching the stored show is removed).
- Q: Does a duplicated scene (SCN-003) get its source's preview? → A: No: the copy is a different file; it shows the placeholder until applied.
- Q: How do previews look to VoiceOver? → A: Decorative: no label, no extra stop; each row's label and value are unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I see what each scene looks like (Priority: P1) — MVP

A performer saves the current look as a scene and steps through the show. Opening the scene switcher
(or Scene Folders), each scene that has been shown has a small picture of how it looked; scenes not yet
shown have a placeholder. After relaunching, the pictures are still there.

**Why this priority**: It is the row's behaviour.

**Independent Test**: With an injected capture source returning a known image per scene state, save
and apply scenes and check the stored preview equals the captured image and is keyed to the scene's
content hash; reopen the store and check it is still there.

**Acceptance Scenarios**:

1. **Given** the live output, **When** scene S is saved, **Then** S's preview equals the captured image and is keyed to S's file hash.
2. **Given** a scene without a preview, **When** its cue is applied and 1 s passes, **Then** it has a preview.
3. **Given** previews stored, **When** the app is relaunched, **Then** the same previews are shown.
4. **Given** a scene never applied or saved on this device, **When** its row is shown, **Then** a placeholder is shown.

---

### User Story 2 - A changed scene never shows an old picture (Priority: P1)

The performer edits scene S (a parameter changes and the file is saved again). Its old picture is gone
at once and the row shows the placeholder until S is shown again, when a new picture is captured.
Other scenes keep their pictures.

**Independent Test**: Edit S's file through the show and check the old preview's entry and file are
removed, a new capture is keyed to the new hash, and neighbours are untouched.

**Acceptance Scenarios**:

1. **Given** S with a preview, **When** S is edited and saved, **Then** the old preview and its file are gone and S shows the placeholder.
2. **Given** that, **When** S is applied again, **Then** the new preview is keyed to the new hash.
3. **Given** scenes T and U with previews, **When** S is edited, **Then** T's and U's previews are unchanged.
4. **Given** S with a preview, **When** its last cue is removed, **Then** its preview and file are removed.

---

### User Story 3 - The picture is in the lists (Priority: P2)

**Independent Test**: A UI test (under 30 s) applies a cue through the switcher with a DEBUG fixture
capture and sees that row show an image while another row shows a placeholder.

**Acceptance Scenarios**:

1. **Given** a scene with a preview, **When** the switcher opens, **Then** its row shows the picture; VoiceOver reads the same label and value as before.
2. **Given** a scene with a preview, **When** Scene Folders lists it, **Then** its row shows the picture in place of the icon.

### Edge Cases

- The output is blacked out or paused when the settle ends: no capture; the placeholder stays.
- The user changes a setting during the settle: no capture (the picture would not match the scene).
- Another scene is applied during the settle: the first capture is cancelled.
- No frame arrives within 1 s, or the frame cannot be encoded: no preview; nothing is reported to the user.
- The scene's file cannot be read (Scene missing): no capture, placeholder.
- The index is unreadable or from a newer app: the cache starts empty (PRE-001 repair), no error.
- Clear Caches removes the folder: rows show placeholders; the next capture recreates it.
- Two cues showing the same scene share its preview.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-006-R1**: When a scene is stored by Add Current Scene, the app MUST capture the live output's next frame and store it as that scene's preview.
- **SCN-006-R2**: When a scene is applied through the cue path, the app MUST capture the live output after a 1 s settle and store it as that scene's preview, replacing an earlier preview of the same file.
- **SCN-006-R3**: A capture MUST be dropped when, at capture time, the scene is no longer the applied one, its file hash changed, the live look changed since the apply, the output is not live, or no frame arrived in time. A later apply MUST cancel a pending capture. A capture MUST NOT start while a user Save Frame is in progress.
- **SCN-006-R4**: A preview MUST be identified by the scene ID and the SHA-256 of the scene file's bytes (plus a preview format version); a preview is shown only when its hash equals the stored file's current hash.
- **SCN-006-R5**: When a scene's file changes, the app MUST remove that scene's previews for any other hash (index entries and files) and leave every other scene's previews untouched.
- **SCN-006-R6**: When a scene leaves the show, the app MUST remove all of its previews; at launch the app MUST remove every preview that does not match a stored scene's current hash.
- **SCN-006-R7**: Previews MUST be stored as PNG files of 192 × 108 pixels (centre crop of the frame to 16:9) with a versioned index in `Library/Caches/ScenePreviews`, excluded from backup. Opening MUST repair the index like PRE-001 (missing, unreadable, newer schema, other version, missing or orphan files) and never fail.
- **SCN-006-R8**: The UIX-002 switcher rows and the SCN-004 Scene Folders scene rows MUST show the scene's preview, or a placeholder when there is none.
- **SCN-006-R9**: The preview and placeholder MUST be decorative: rows keep their accessibility labels, values, actions and identifiers; no new VoiceOver stop.
- **SCN-006-R10**: Previews MUST NOT be included in FILE-005 backups or FILE-001 archives, and MUST be counted and cleared as Caches (FILE-009, FILE-010). No new UserDefaults key, no networking.
- **SCN-006-R11**: DEBUG `-uitestScenePreviewFixture` MUST replace the frame grab with an instant fixture picture so UI tests do not depend on the renderer.

### Key Entities

- **Scene preview key**: scene ID, content hash (SHA-256 hex of the file bytes), preview format version; its stable ID names the file.
- **Scene preview store**: the index (schema version, format version, entries: scene ID, hash, version, file name, size) and the PNG files.
- **Capture request**: scene ID, hash and live look at the apply, the settle delay.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-006-S1**: After saving a scene, its stored preview is byte-identical to the captured picture and keyed to the scene file's hash (acceptance test).
- **SCN-006-S2**: After an edit, 0 previews of the old content remain (entries and files), the next capture is keyed to the new hash, and 100% of other scenes' previews are unchanged.
- **SCN-006-S3**: Previews survive a relaunch (the store reopened from disk returns the same files).
- **SCN-006-S4**: A switcher row shows a preview within a UI test that finishes in under 30 s.
- **SCN-006-S5**: VoiceOver labels and values of switcher and Scene Folders rows are unchanged.

## Assumptions

- Scenes are edited only by writing their file through the show (Add, SCN-003 Rename, Duplicate, restore and import); any such write goes through the show coordinator, which reports it.
- Simulator results are not device evidence; the frame grab's real pictures on devices are covered by REC-001.
- Capturing a 192 × 108 crop costs one frame read-back of the output; at most one per apply.
