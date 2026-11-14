# Feature Specification: UIX-011 Color Palette Picker

**Feature Branch**: `feature/uix-011` (spec directory `225-uix-011-color-palette-picker`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement UIX-011 (Color palette picker) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Create and save local palettes with swatches and gradients." Acceptance, verbatim:
"Palette changes update linked layers and survive relaunch." P1, depends on SCN-001."

Identifiers in this feature carry the roadmap ID: requirements `UIX-011-R1…`, success criteria `UIX-011-S1…`,
research decisions `UIX-011-D1…`, tasks `UIX-011-T01…`. Other features are cited by their own IDs: SCN-001
(versioned scene document), SCN-002 (autosave), SCN-010 (scene history), VIS-001…VIS-009 (native visuals),
ACC-003 (colour-blind-safe palette), ACC-012 (sensory safety profile), FX-003 (colour grade), CMP-008 (gradient
masks), FILE-005 (library backup), FILE-009 (storage usage), FILE-011 (local data erase).

## Baseline: what exists today (audit of 2026-11-14, commit `0ec67c56`)

| Question | Today |
|---|---|
| Palettes | VIS-001 `VisualPalette` (VisualGenerators): a fixed enum of four palettes (`spectrum` hue ramp, `ice`, `mono`, ACC-003 `colorBlindSafe`), each defined in sRGB and interpolated in linear light. Its header says "Full palette editing is UIX-011". No user palettes, no file. |
| Who draws with a palette | The nine native generators (circular and linear spectrum, oscilloscope, Lissajous, radial waveform, beat rings, mandala, particle fountain, particle orbit) read `configuration.palette.color(bar:of:)`; `NativeSpectrumHost.palette` applies one palette to the generator on screen. The compositor scenes (Photo, Video, Text) draw their spectrum layer with the default palette. |
| Choosing one | Only ACC-003's Settings switch "Colour-blind safe palette" (`settings.visual.colorBlindSafePalette`, never erased, kept by every erase), which swaps `spectrum` for `colorBlindSafe`. |
| Colour grade (FX-003) | A whole-frame grade (temperature, lift, gamma, gain, saturation, hue) in the effect chain; it does not choose bar colours. |
| Gradient stops (CMP-008) | Alpha-only stops (position, alpha; 2…8 stops) on a layer's gradient mask; no colour stops. |
| Scene document (SCN-001) | Layers carry `extra` (unknown fields kept verbatim) and the document carries top-level `extra`; adding a field there needs no version bump and no decoder change. QA-004's meta-test covers the decode and migration error enums only. |
| Backup, storage, erase | FILE-005 backs up Show, Scenes, UserPresets, PresetCollections (+ tags, overrides) and Photos as checksummed records; FILE-009 measures folders per category; FILE-011 erases folders per category ("Scenes and show" = Show + Scenes). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where are palettes kept? → A: In one local palette library file in the app's Application Support (`Palettes/palettes.json`) with a format name and schema version. Nothing leaves the device; no network, no new setting key.
- Q: How many palettes and colours? → A: At most 64 user palettes, each with 2…8 colours and a name of 1…40 characters. Built-in palettes (Spectrum, Ice, Mono, Colour-blind safe) are always present, read-only and never stored in the file.
- Q: What is a "swatch" and what is a "gradient"? → A: A palette is an ordered list of colour swatches plus a style: Gradient blends evenly between the swatches (in linear light, as VIS-001 does); Swatches uses each colour as a solid band. The editor shows a gradient preview of the result.
- Q: How do layers use a palette? → A: By link: the scene stores a palette ID on the scene (for visuals without a layer) and on each palette-drawing layer (`palette` field). Editing a palette changes every linked layer at once; no colours are copied into scenes.
- Q: What happens when a linked palette is deleted? → A: The link is kept in the scene (a restored backup brings the palette back), the layer draws with the default palette, and the palette screen shows a notice "This scene's palette is missing. Spectrum is used." which VoiceOver also announces once.
- Q: Does ACC-003's colour-blind-safe switch still win? → A: Yes. While it is on, every native visual draws with the colour-blind-safe palette whatever is linked (accessibility first); the link is kept.
- Q: Where do palettes go in backup and erase? → A: The palette library is backed up and restored by FILE-005 (one record per palette, the usual Keep both / Replace / Skip choices); FILE-011 erases it with "Scenes and show"; FILE-009 counts it under Scenes.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How are swatch colours stored? → A: As 8-bit sRGB hex text (`#RRGGBB`), opaque. The system colour picker's result is converted to sRGB and rounded; alpha is not offered (layer opacity is CMP-002's job).
- Q: Which IDs do palettes have? → A: User palettes get a canonical uppercase UUID at creation, kept through renames and edits; a duplicate gets a new UUID. Built-ins use fixed IDs `builtin.spectrum`, `builtin.ice`, `builtin.mono`, `builtin.colorBlindSafe`, and draw exactly as VIS-001 draws them today.
- Q: How does the Swatches style map colours onto bars, rings and particles? → A: Evenly: with n colours, the first 1/n of the positions take colour 1, the next 1/n colour 2, and so on (no cycling), so a 2-colour palette splits a spectrum in half.
- Q: Is a palette edit undoable? → A: No. Palette edits change the library, not the scene (the editor has explicit add, remove and delete actions; delete asks for confirmation). Choosing the scene's palette is a scene edit and is undoable.
- Q: How does a restore treat a palette that exists on both sides with different content? → A: Like other keyed records: Keep both (default) adds the backup's palette as a copy under a derived ID and "<name> copy"; Replace takes the backup's content under the same ID; Skip keeps the device's. If the copy would exceed 64 palettes, the device's palette is kept (`fellBack`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Make my own palette and see it on the visual (Priority: P1) — MVP

I open Settings › Palettes, create a palette, pick its colours one swatch at a time (with the system colour
picker or a list of named colours), choose Gradient or Swatches, and select it for the scene. The visual on
screen draws with it at once. When I change a colour later, the visual changes with it.

**Why this priority**: it is the whole roadmap row.

**Independent Test**: create a palette, link it to a scene with two palette layers, change one swatch: both
layers' colours change immediately; relaunch: the palette, its colours and the links are unchanged.

**Acceptance Scenarios**:

1. **Given** a scene linked to my palette, **When** I change a swatch, **Then** every layer linked to that palette draws the new colour from the next frame.
2. **Given** my palettes and a linked scene, **When** the app is quit and opened again, **Then** the same palettes, colours, styles and links are there and resolve to the same colours.
3. **Given** a built-in palette, **When** I try to edit it, **Then** I can only duplicate it; the copy is editable.

### User Story 2 - Manage palettes (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a user palette, **When** I rename, duplicate or delete it, **Then** the list updates and the file is saved.
2. **Given** 64 user palettes, **When** I try to create another, **Then** I am told the limit and nothing is created.
3. **Given** the scene's palette was deleted, **When** I look at the visual, **Then** it uses Spectrum and the palette screen says the scene's palette is missing.

### User Story 3 - Accessible editing (Priority: P2)

**Acceptance Scenarios**:

1. **Given** VoiceOver, **When** I move over a swatch, **Then** it reads "Colour 2 of 4, teal, #008080" rather than numbers only.
2. **Given** a swatch darker than 3:1 against black, **Then** the row says "Low contrast on black".

### Edge Cases

- A damaged palette file: readable palettes are kept, damaged entries are dropped and the app says how many; a file from a newer app version is never overwritten (editing is off until the app is updated).
- Duplicate IDs in the file: the first wins.
- A palette with one colour, more than 8, or an empty name in the file is dropped as damaged.
- A scene that links an unknown or missing palette ID draws the default palette and is not changed.
- A palette edit is not a scene edit: it is not undone by scene undo (SCN-010); choosing the scene's palette is.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-011-R1**: The app MUST keep a local palette library: built-in palettes (read-only) plus at most 64 user palettes, each with an ID, a name (1…40 characters), a style (gradient or swatches) and 2…8 sRGB colours.
- **UIX-011-R2**: User palettes MUST be saved to one versioned file in Application Support after every change, and read back at launch; damaged entries are dropped and counted, and a newer-version file is never overwritten.
- **UIX-011-R3**: The user MUST be able to create, rename, duplicate, delete and edit user palettes (set, add and remove colours down to 2 and up to 8, change the style); built-in palettes can only be duplicated.
- **UIX-011-R4**: A scene MUST link to a palette by ID: on the document (for visuals without a layer) and on each palette-drawing layer. The links are optional fields with no format version change; scenes without them behave as before.
- **UIX-011-R5**: A layer's colours MUST resolve as: the layer's link, else the scene's link, else the default palette (Spectrum); a link to a missing palette resolves to the default and is reported as missing.
- **UIX-011-R6**: Changing a linked palette MUST update every linked layer's colours immediately, without re-saving the scene.
- **UIX-011-R7**: Choosing the scene's palette MUST be a scene edit (saved by SCN-002, undoable by SCN-010).
- **UIX-011-R8**: ACC-003's colour-blind-safe switch MUST override any link while it is on.
- **UIX-011-R9**: The swatch editor MUST offer the system colour picker and a list of named colours, read each swatch to VoiceOver as position, colour name and hex, mark swatches under 3:1 contrast on black, and show a gradient preview. ACC-012's sensory safety limits keep applying to whatever palette is drawn.
- **UIX-011-R10**: A missing scene palette MUST be shown as a notice on the palette screen and announced once through the shared announcer.
- **UIX-011-R11**: The palette library MUST be part of the FILE-005 library backup and restore (per-palette records with the usual choices), erased by FILE-011 with "Scenes and show", and measured by FILE-009 under Scenes.

### Key Entities

- **Colour palette**: ID, name, style, ordered colours (sRGB, 8 bits per channel), built-in flag.
- **Palette library**: the built-ins plus the user palettes, with a format name and schema version.
- **Palette link**: a palette ID on a scene or on one of its layers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-011-S1**: After one swatch edit, two layers linked to the palette resolve to the new colours with no other action.
- **UIX-011-S2**: After a relaunch (a new library reading the file and the scene read back), the palette and every link resolve to exactly the colours they had before.
- **UIX-011-S3**: A user creates a palette and changes one swatch in under a minute, with or without VoiceOver.
- **UIX-011-S4**: A backup made with palettes and restored into an empty library gives the same palettes.

## Assumptions

- The palette drives the native visuals (VIS-001…VIS-009) and the spectrum layers; the compositor scenes' spectrum layer keeps its default palette until a later row wires compositor palettes (the link is still saved).
- projectM presets have their own colours and are not affected.
- Palette editing needs no new UserDefaults key.
