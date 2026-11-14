# Feature Specification: SCN-011 Scene Template Gallery

**Feature Branch**: `feature/scn-011` (spec directory `181-scn-011-template-gallery`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SCN-011 (P1, size M, depends on SCN-001, integrated). Observable behavior,
verbatim: "Bundle a small licensed set of editable starter scenes." Acceptance, verbatim: "Template
instantiation creates independent local copy."

Identifiers carry the roadmap ID: requirements `SCN-011-R1…`, success criteria `SCN-011-S1…`, tasks
`SCN-011-T01…`, research decisions `SCN-011-D1…`. Other features are cited by their own IDs: SCN-001
(scene document), SHOW-001 (show and cues), SCN-003 (duplicate scene), SCN-004/005/006 (folders, tags,
previews), SCN-007 (cue transitions), SCN-012 (repair report), FILE-001 (scene archives), ACC-004
(announcer lanes), FR-070 (accessibility), Constitution (no unlicensed media).

## Baseline: what exists today (audit of 2026-11-14, commit `6b32708e`)

| Area | Today |
|---|---|
| Scene document (SCN-001) | `SceneDocument` decodes canonical JSON (`projectm-ios.scene`, version 1) with layers, MOD-001 parameters, bindings, assets; `duplicated(newID:name:)` makes a copy under a new ID. |
| Show store (SHOW-001) | `ShowStore`: `show.json` plus `Scenes/<ID>.scene.json`, each written whole; cues refer to scenes by ID; scene files no cue uses are removed on save. |
| Duplicate (SCN-003) | `ShowStore.duplicateScene` writes a copy under a new ID, never over another file; `ShowCoordinator.duplicateScene` inserts its cue, copies folder and tags, reports `sceneFilesChanged`. |
| What a cue applies (SHOW-001-D5) | The visual from the layer kinds (circular spectrum, linear spectrum, text over circular spectrum, photo, video; no layer = projectM), seven app-held values (bar count, orientation, spacing, glow on/intensity/radius/threshold) and the text layer's spec. The oscilloscope and Lissajous visuals are not scene layers (VIS-003-R12, VIS-004-R12). Bindings are kept in the file but not applied by a cue. |
| Folders, tags, previews (SCN-004/005/006) | Logical folders and tags live in `show.json`; previews are captured at runtime after a scene is applied. |
| Archives (FILE-001) | `.pmscene` import/export; templates do not need an archive (no media). |
| Licenses screen | Lists the third-party texts in `Resources/Licenses` (engine, presets, ANGLE). The app's own code and content are MIT (repository `LICENSE`). |
| Preset packs | Submodules under `Vendor/presets` with their own licences; a scene does not record a projectM preset. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What may a template contain? → A: Only content the project owns: the app's native visuals (circular and linear spectrum), the seven app-held values, and text written for the project, rendered in the system font. No photos, videos, logos, generator graphs, materials, camera layers, projectM presets or third-party images. All template content is MIT (the repository licence); no third-party asset is bundled, so the Licenses screen needs no new entry.
- Q: Which templates? → A: Five: "Pulse Rings" (circular spectrum, 64 bars, strong glow), "Spectrum Bars" (vertical linear spectrum), "Horizon Bars" (horizontal linear spectrum with a soft glow), "Title Card" (generated title text over a circular spectrum) and "Show Starter" (two scenes, opening and title, with a 1.5 s crossfade into the second cue). "Oscilloscope trails" and "Lissajous stereo" are left out: those visuals are not scene layers, so a cue could not show them (recorded, not built).
- Q: Kick binding in "Pulse Rings"? → A: Left out: a cue does not apply bindings today, so a binding would promise behaviour the copy does not have.
- Q: Where do templates live? → A: Read-only `.scene.json` files plus a `manifest.json` in the app bundle (`SceneTemplates/`). The manifest names each template, its description, its preview symbol, its scenes (file, cue label, optional transition) and every asset with its source and licence.
- Q: Preview? → A: A symbol and the template's name in the gallery (SF Symbols, part of the system; no bundled image). After instantiation, SCN-006 captures the copy's preview at runtime the first time it is shown.
- Q: Where is the gallery? → A: Settings → Show → "Add from Template…" (a sheet). Not in the scene switcher (smaller change in shared files).
- Q: What does choosing a template do? → A: For each of its scenes: a new scene ID, a copy written into the show store (never over an existing file), a cue appended with the template's label and transition, and the tag "template" (SCN-005). Nothing is applied; the position stays (SHOW-001-R6). The bundled files are never written. All or nothing: when the show cannot hold every cue, nothing is written.
- Q: Names? → A: The copy keeps the template's scene name ("Pulse Rings"); a second copy has the same name and a different ID (Duplicate's "copy" naming is for duplicates of the user's own scenes).
- Q: Announcements? → A: "Added <template> from templates." or the refusal, on the library lane (ACC-004, `.library`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start from a template (Priority: P1)

A performer with an empty or short show opens Settings → Show → Add from Template…, picks "Pulse Rings" and gets a new cue whose scene is a local copy they can change.

**Why this priority**: It is the roadmap row: editable starter scenes.

**Independent Test**: Instantiate a template into an empty show; one cue appears, its scene is stored under a new ID, and stepping to it shows the template's look.

**Acceptance Scenarios**:

1. **Given** a show, **When** the user picks a template, **Then** one cue per template scene is appended, each scene stored under a new scene ID, tagged "template", and the output does not change.
2. **Given** the same template instantiated twice, **When** the stored scenes are listed, **Then** there are two distinct scene IDs and two separate files.
3. **Given** two copies, **When** copy 1 is changed and saved, **Then** copy 2 and the bundled template are byte-identical to before.
4. **Given** two copies, **When** copy 1's cue is deleted, **Then** copy 2 still loads.

### User Story 2 - Show Starter (Priority: P2)

The user picks "Show Starter" and gets two cues, the second fading in over 1.5 s.

**Independent Test**: Instantiate it; two cues are appended in order, the second with a crossfade transition.

**Acceptance Scenarios**:

1. **Given** a show with 255 cues, **When** the user picks "Show Starter", **Then** nothing is written and the refusal is shown and announced.

### Edge Cases

- The bundle's manifest or a template file cannot be read: that template is not offered; the others are.
- The show is full (256 cues): the button is disabled; a template needing more cues than are free is refused, nothing written.
- A generated scene ID is already stored: refused for that template, nothing written.
- A saved show fails to write: the editor message, as for other edits.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-011-R1**: The app bundles five templates (Clarifications) as read-only scene files with a manifest.
- **SCN-011-R2**: Every template scene decodes as an SCN-001 document with no warnings and validates against the app's parameter registry with no warnings, using only layer kinds `spectrum.circular`, `spectrum.linear` and `text`.
- **SCN-011-R3**: The manifest lists every asset of every template scene with its source and licence; every licence is the project's own (MIT); no asset is a photo, video, logo, preset or third-party image.
- **SCN-011-R4**: Instantiating a template writes a copy of each scene under a new scene ID into the show store, never over an existing file, and appends one cue per scene with the template's label and transition; the copies get the tag "template".
- **SCN-011-R5**: Instantiation never writes the bundled files; editing or deleting a copy never changes the template or another copy.
- **SCN-011-R6**: Instantiation is all or nothing (capacity checked before any file is written) and never applies a scene or moves the position.
- **SCN-011-R7**: The gallery is reached from Settings → Show → "Add from Template…"; each row shows a preview symbol, the name and the description; VoiceOver reads name and description as one element with the hint to add it; results and refusals are announced on the library lane.
- **SCN-011-R8**: Copies report `sceneFilesChanged` so SCN-006 previews follow their files.

### Key Entities

- **Template manifest**: format name, version, templates in display order.
- **Template**: ID, name, description, preview symbol, scenes (file, cue label, optional transition), tags.
- **Template asset record**: scene file, asset key, kind, source, licence.

## Success Criteria *(mandatory)*

- **SCN-011-S1**: Instantiating one template twice gives two distinct scene IDs and two files (acceptance test).
- **SCN-011-S2**: After copy 1 is edited and saved, copy 2's file and the bundled template's file are byte-identical to before; after copy 1 is deleted, copy 2 loads.
- **SCN-011-S3**: 5 of 5 bundled templates decode and validate with zero warnings.
- **SCN-011-S4**: 100% of template assets are listed with a licence in the manifest.
- **SCN-011-S5**: A user adds a template from Settings and sees its cue in under 30 s of UI-test time.

## Assumptions

- Templates are not localized (the app ships in English).
- Template copies are ordinary scenes: duplicate, rename, folders, tags, MIDI and transitions apply as to any scene.
- No device evidence is needed: the feature is file and UI logic, tested on the host and simulator.
