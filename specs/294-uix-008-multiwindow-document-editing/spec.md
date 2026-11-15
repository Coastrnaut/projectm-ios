# Feature Specification: UIX-008 Multiwindow Document Editing

**Feature Branch**: `feature/uix-008` (spec directory `294-uix-008-multiwindow-document-editing`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (UIX-008-T01-T15 verified on the Mac: app tests and a UI test on the own iOS 27.2
iPad simulator "UIX8 iPad Pro"; T16 `{device}` open, D2/D3 with Stage Manager)

**Input**: User description: "Implement UIX-008 (Multiwindow document editing) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Allow multiple scene documents where iPadOS
supports it." Acceptance, verbatim: "Two scenes edit independently and save to separate files." P2, size L,
depends on SCN-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `UIX-008-R1…`, success criteria `UIX-008-S1…`,
tasks `UIX-008-T01…`, research decisions `UIX-008-D1…`. Other features are cited by their own IDs: SCN-001 (scene
document format), SCN-002 (autosave of the live look, `current.scene`), SCN-003 (duplicate and rename), SCN-004
(scene folders), SCN-006 (scene previews), SCN-010 (undo and redo), SCN-012 (validation and repair), SCN-015
(scene lock), SHOW-001 (the show and its stored scenes), OUT-001 (external display scene), UIX-007 (split
preview/editor), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-15, commit `7bcd5c34`)

| Area | Today |
|---|---|
| Windows | One SwiftUI `WindowGroup` showing `RootView` over the single `AppCoordinator`. Info.plist sets `UIApplicationSupportsMultipleScenes` to false; iPadOS offers no second window. |
| External display | OUT-001: the Info.plist configures only the non-interactive external display role (`ExternalDisplaySceneDelegate`, iOS 26); on iOS 27 a SwiftUI scene accessory on the main window's content. The application role stays with the window group. |
| Engine and capture | `AppCoordinator` owns the one `CaptureManager` (created in its initializer) and the one ANGLE renderer (`prepareRenderer`, created once). Only the app's `@State` creates an `AppCoordinator`. |
| Saved scenes (the library) | SHOW-001 `ShowStore`: `Show/show.json` (the index: cues, SCN-004 folders, SCN-005 tags) and one file per scene, `Show/Scenes/<SCENE-ID>.scene.json` (canonical SCN-001 bytes, written whole and atomically). `ShowCoordinator` (main actor) caches each scene's name (`sceneNames`). |
| Editing a stored scene | SCN-003 Rename rewrites one scene file; SHOW-006 rehearsal writes parameter values into one scene file. Both never apply anything to the live output. There is no editor for a stored scene's document. |
| Undo | SCN-010 `SceneHistory<Value>` (SceneFormat, pure): bounded undo/redo of canonical scene bytes with coalescing keys; the app uses it for the live look only. |
| Scene library UI | SCN-004 Scene Folders (Settings → Show → Scene Folders) lists stored scenes with a context menu, swipe actions and accessibility actions (Move to, Go to Cue, Tags, Export). |
| Split editor | UIX-007 keeps the live output beside Settings on iPad, in the one window. |

The gap is real: there is one window and no document editor for stored scenes.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is a "scene document" here? → A: A saved scene in the library: a SHOW-001 stored scene (one file per
  scene ID). The live look (SCN-002 `current.scene`) is not a document window; it stays the main window's.
- Q: What does a second window show? → A: A scene editor window for one saved scene, opened with "Open in New
  Window" from Scene Folders. The main window stays the single live performance window with the one engine,
  capture and outputs.
- Q: Does an editor window render live visuals? → A: No. There is one engine and one capture; an editor window
  shows the scene's stored preview picture (SCN-006) when one exists and never starts a renderer, capture,
  camera or audio. Saving never applies the scene to the live output.
- Q: What can be edited in an editor window? → A: The scene's name (SCN-003 name rules) and each layer's
  opacity (0-100 %). Both edits cannot make a valid scene invalid, so saving needs no repair step. Richer
  editing stays in the main window. Rejected: the whole layer inspector per window (it is bound to the live
  engine).
- Q: Can the same scene be open in two windows? → A: No. Opening a scene that already has an editor window
  brings that window forward; a second editor for the same scene is never created.
- Q: What happens on iPhone? → A: iPhone has no multiple windows: "Open in New Window" is not offered and
  nothing else changes.
- Q: Undo? → A: Each editor window has its own undo and redo history (SCN-010 bounds), independent of other
  windows and of the live look's history.

### Session 2026-11-15 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: When the main window steps to a cue whose scene has an editor window open with unsaved edits, what does it
  show? → A: The saved file only. Unsaved edits live in the editor window until Save; the main window never
  reads an editor's model. Rejected: applying unsaved edits live (it would make a window a second performer).
- Q: When the system creates a second main window, which one performs? → A: The first main window to appear
  claims the performance role; any other shows "projectM is open in another window" with nothing live. When the
  performing window closes, the next main window on screen takes the role.
- Q: What happens to unsaved edits when an editor window is closed? → A: They are discarded; the file stays as
  last saved. iPadOS gives an app no way to stop a window closing, so the window shows "Unsaved changes" under
  its title while dirty and VoiceOver reads it. Rejected: autosaving on close (a half-finished edit would
  silently replace the stored scene).
- Q: How is a conflict with a change made elsewhere resolved? → A: Save compares the file's current bytes with
  the bytes the editor loaded (or last saved); if they differ it writes nothing and offers Replace (write this
  window's document) or Reload (discard this window's edits and read the file). Rejected: last writer wins
  silently.
- Q: Is the number of editor windows limited? → A: No app limit beyond iPadOS's; each editor holds one scene
  document (at most 1 MiB) and its SCN-010-bounded history (at most 4 MB).

### Session 2026-11-15 (speckit-implement)

- Q: Are editor windows restored after a relaunch? → A: Yes, by the system from the scene ID; a restored window
  reads the file again (unsaved edits are gone, as on close). DEBUG UI-test runs (`-uitestResetNotice`) close a
  restored editor window and bring the main window back, so each UI test starts on the main window (ADR-0105
  decision 7).
- Q: Does the feature add stored settings? → A: No UserDefaults keys. Editor windows are marked in their scene
  session's `userInfo` only, which the system keeps with the window.
- Q: Is the two-window case automated on the simulator? → A: Partly. The UI test opens an editor window from
  Scene Folders, edits and saves it and checks the stored file; with no Stage Manager on the simulator the second
  window takes the screen, so two editor windows side by side are checked on D2 and D3 (UIX-008-T16 `{device}`).
  Two editors editing and saving independently is proven by the app tests.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Edit two saved scenes side by side (Priority: P1)

On an iPad, a performer opens two saved scenes from Scene Folders, each in its own window, renames one and
changes a layer's opacity in the other, and saves each. Each scene's file holds exactly that window's changes.

**Why this priority**: It is the roadmap acceptance: two scenes edit independently and save to separate files.

**Independent Test**: Create two editors for two library scenes, edit each, save each; read both files back.

**Acceptance Scenarios**:

1. **Given** two saved scenes A and B, **When** A's window renames A and B's window sets a layer of B to 40 %,
   **Then** B's name and A's opacities are unchanged in the other window.
2. **Given** both windows have edits, **When** each saves, **Then** A's file and B's file each decode to that
   window's document, and the library lists both under their saved names.
3. **Given** edits in both windows, **When** one window undoes, **Then** only that window's last edit is undone.

### User Story 2 - One window per scene, one live output (Priority: P1)

Opening a scene that is already open brings its window forward. Opening editor windows never starts a second
visualizer, capture or output.

**Independent Test**: Request the same scene twice through the window routing; count engines and captures before
and after creating editors.

**Acceptance Scenarios**:

1. **Given** scene A's editor window is open, **When** "Open in New Window" is chosen for A again, **Then** the
   existing window is brought forward and no second editor exists.
2. **Given** the app is running, **When** editor windows are opened, **Then** the number of engines and captures
   is unchanged.
3. **Given** a second main window is created by the system (for example from the app switcher), **Then** it
   shows a notice that the performance window is open elsewhere and never a second visualizer.

### User Story 3 - Safe saving (Priority: P2)

A save never half-writes a file, never touches another scene's file, and does not silently overwrite a change made
to the same file elsewhere (for example a rename in the main window) after the editor opened it.

**Acceptance Scenarios**:

1. **Given** the scene lock (SCN-015) is on, **When** an editor saves, **Then** the save is refused with the
   lock's message and the file is unchanged.
2. **Given** the scene's file changed after the editor loaded it, **When** the editor saves, **Then** it reports a
   conflict and offers Replace or Reload; nothing is written until one is chosen.
3. **Given** a window with unsaved edits, **When** the user closes it, **Then** the edits are discarded and the
   file is unchanged (the window shows an "Unsaved changes" marker while dirty).

### Edge Cases

- The scene's file is missing or unreadable when the window opens: the window says so and offers nothing to edit.
- The scene is removed from the library while its window is open: Save reports that the scene is no longer
  stored and writes nothing.
- An invalid name (empty, too long, several lines): refused with SCN-003's message; the name is unchanged.
- State restoration brings back an editor window for a scene that no longer exists: it shows the missing message.
- The performing main window closes while another main window is on screen: that window takes the role.
- An external display connected while editor windows are open: the external output still follows the main
  window only (OUT-001).

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-008-R1**: On devices that support multiple windows, Scene Folders MUST offer "Open in New Window" for each
  readable saved scene (context menu, swipe action and accessibility action). On devices that do not, it MUST NOT
  be offered.
- **UIX-008-R2**: An editor window MUST edit exactly one saved scene through its own document model; models for
  different scenes MUST share no mutable state except the library index.
- **UIX-008-R3**: An editor window MUST allow renaming the scene (SCN-003 name rules) and setting each layer's
  opacity from 0 to 100 %.
- **UIX-008-R4**: Each editor window MUST have its own undo and redo history with SCN-010's bounds; consecutive
  changes to the same field coalesce into one step.
- **UIX-008-R5**: Save MUST write only that scene's file, whole and atomically, in the SCN-001 format, and then
  update the library's cached name and the scene's preview state (SCN-006). Save MUST NOT apply anything to the
  live output.
- **UIX-008-R6**: At most one editor window per scene: a request for an open scene MUST bring its window
  forward.
- **UIX-008-R7**: Opening or using editor windows MUST NOT create an engine, renderer, audio capture, camera or
  external output; only the main window performs.
- **UIX-008-R8**: Only one window MUST be the performance window; any other main window the system creates MUST
  show a short notice instead of the visualizer.
- **UIX-008-R9**: Save MUST be refused while the scene lock (SCN-015) is on, and MUST report a conflict instead
  of writing when the stored file changed since the editor loaded or last saved it.
- **UIX-008-R10**: The external display (OUT-001) MUST keep working with multiple windows enabled.
- **UIX-008-R11**: Editor windows MUST meet FR-070: every control labelled for VoiceOver, Dynamic Type, and the
  opacity slider through the ACC-005 accessible-parameter helper.
- **UIX-008-R12**: The main window MUST read only saved scene files; an editor's unsaved edits never reach the
  live output.

### Key Entities

- **Scene editor window ID**: the saved scene's ID; it identifies the window (and restores it).
- **Scene document editor**: one window's model: the loaded document, the stored bytes it was loaded from, its
  undo history and whether it has unsaved edits.
- **Window routing**: which scene IDs have an open editor; decides between opening and bringing forward.
- **Performance window claim**: which main window is the performance window.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-008-S1**: Two editors on two scenes: every edit in one leaves the other's document byte-identical; after
  saving, each file's bytes equal its editor's document, and the library lists both names.
- **UIX-008-S2**: Undo in one editor changes only that editor (the other's history is unchanged).
- **UIX-008-S3**: Requesting an open scene a second time creates no second editor (routing test).
- **UIX-008-S4**: Creating and using editors creates zero engines and zero captures (instance counts).
- **UIX-008-S5**: The OUT-001 external display UI tests still pass with multiple windows enabled.
- **UIX-008-S6**: On an iPad simulator, opening an editor window from Scene Folders, editing and saving changes
  that scene's file (UI test, under 30 s); two windows visible at once is a `{device}` check with Stage Manager.

## Assumptions

- iPadOS decides window placement; on iPad without Stage Manager a new window takes the screen and the user
  switches back through the app switcher.
- Simulator results are not device evidence; D2 and D3 with Stage Manager are device tasks.
- No new UserDefaults keys are needed (window state is restored by the system from the scene ID).
