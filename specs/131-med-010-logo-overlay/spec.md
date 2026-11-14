# Feature Specification: MED-010 Logo Overlay

**Feature Branch**: `feature/med-010` (spec directory `131-med-010-logo-overlay`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-010 (Logo overlay) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Add local transparent image as a
reusable logo asset." Acceptance, verbatim: "PNG alpha survives import, compositing and scene
export." Verification: simulator fixture media plus the device picker. Depends on MED-001
(integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-010-R1…`, success criteria `MED-010-S1…`, tasks `MED-010-T01…`. Other
features are cited by their own IDs: MED-001 (photo import, sanitizer, photo layer), MED-014 (safe
decoder), FILE-008 (content-addressed photo folder, ADR-0043), MED-006 (slideshow references in the
same folder), CMP-001/002 (compositor and layer stack), CMP-003 (opacity), CMP-006 (fit and anchor
maths), CMP-013 (render caching), CMP-015 (layer inspector), FX-002/FX-003 (output pass), REC-001 and
REC-003 (capture and recording), FILE-001/FILE-002 (scene archives), FILE-003 (import dry run),
FILE-005 (library backup), FILE-011 (local data erase), SCN-001/002/010/012 (scenes, autosave, undo,
repair), SHOW-001 (show cues), ACC-005 (accessible parameters), ACC-011 (announcer).

## Baseline: what exists today (audit of 2026-11-14, commit `3c373722`)

The row's gap status is "Gap candidate". The audit confirms the gap: nothing shows an image over the
other visuals, and the app keeps no image that is meant to be reused.

| Area | Behaviour today | Gap for this row |
|---|---|---|
| Import and sanitizer (MED-001, MED-014) | The decoder draws the picture into 8-bit premultiplied sRGB and un-premultiplies it (straight alpha, alpha bytes exact). The sanitizer writes **PNG when any pixel is not opaque** (alpha kept, lossless) and **JPEG at quality 0.9 otherwise**. Limits: 40 MB, 100 million pixels, stored at most 4096 px. | Alpha already survives a PNG import; an opaque logo would become a lossy JPEG. Nothing marks an image as a logo or caps its size for one. |
| Photo layer upload (MED-001) | `ImageLayerSource` uploads the **straight-alpha** pixels into an `rgba8Unorm_srgb` texture, builds mipmaps from them and premultiplies **after** sampling. | Filtering straight alpha mixes the RGB of fully transparent pixels (stored as black) into edge texels, so a soft-edged logo scaled down would get dark fringes. A logo needs premultiplied (linear) texels before any filtering. |
| Photo folder (FILE-008, MED-006) | Content-addressed payloads plus `references.json`; the current photo is `settings.photo.id`; MED-006 slides are protected references (`SlideshowStore.protectedIDs`). | No logo reference, so a new photo or Remove Photo would release a logo that shared its picture. |
| Compositor visuals | Photo, Video, Camera and Text each own a CMP-001 compositor with a fixed two-layer stack (premultiplied linear `rgba16Float`, "over"). The native spectra (Circular, Linear, Oscilloscope) draw directly, and projectM draws through ANGLE, without a compositor. | No layer above the content. |
| Scenes (SCN-001) | Asset types `photo`, `video`, `text`, `generatorGraph`; unknown asset types are kept with a warning. An asset no layer uses gets an `unusedAsset` warning. | No logo asset. |
| Scene archives (FILE-001/002) | One scene, at most one photo and one video (3 files). | No logo file. |
| Backup and erase (FILE-005, FILE-011) | The Photos folder is backed up (every resolving reference) and erased by "Photos and videos" with `settings.photo.id` and the slideshow key. | No logo keys. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Where is the logo stored? → A: As one more FILE-008 reference in the existing Photos folder
  (the "kind" is the settings key that names it, `settings.logo.id`), not a new folder. The folder
  is already backed up, measured, deduplicated and erased; a new folder would need every one of
  those paths again. The logo's reference is protected like MED-006's slides, so a new photo or
  Remove Photo never deletes it (MED-010-R2, R10).
- Q: Which visuals show the logo? → A: The four compositor visuals (Photo, Video, Camera, Text), as
  the top layer of their own compositor, so it is composited in linear light exactly like the
  other layers and appears in captures (REC-001) and recordings (REC-003). projectM and the native
  spectra (Circular, Linear, Oscilloscope) have no compositor; a separate screen overlay there would
  blend in a different space and miss recordings, so they are out of scope for this row and Settings
  says so (MED-010-R5). A later row can move those visuals onto a compositor.
- Q: How is the logo placed? → A: A corner preset (top left, top right, bottom left, bottom right,
  centre) or a custom anchor (two 0…1 fractions); size as a fraction of the shorter side of the
  screen (5 %…50 %, default 15 %), measured along the logo's longer side; margin as a fraction of
  the shorter side (0 %…20 %, default 4 %); opacity 0 %…100 % (default 100 %). Placement is the
  logo layer's own (anchor maths of CMP-006); the CMP-015 layer inspector does not list the logo
  (MED-010-R6, R7).
- Q: How large may a logo be? → A: A picked file of at most 10 MB and at most 16,777,216 pixels
  (4096 × 4096) is accepted; larger ones are refused with a notice. The stored copy is scaled down
  to at most 1024 px on its longer side (a logo never covers more than half the shorter side of a
  screen; 1024 px keeps the GPU copy at about 8 MB with mipmaps) (MED-010-R3).
- Q: In which format is the logo stored? → A: Always PNG, whether or not it has transparency, so
  it is lossless and alpha is never dropped by a JPEG re-encode (MED-010-R3).

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rules 4 and 9).

- Q: When a saved scene is opened (relaunch, Reopen, a show cue), does its logo replace the current
  one? → A: Yes when the scene has a logo asset whose picture is on the device: its identifier and
  placement become current. A scene without a logo asset, or whose logo picture is missing, leaves
  the current logo unchanged (the missing one is in the repair report). Undo and redo do not change
  the logo (it is a stored picture, like the MED-001 photo, which is not undoable) (MED-010-R10).
- Q: Which picked formats are accepted as a logo? → A: Every still format the MED-014 decoder reads
  (PNG, HEIC/HEIF with alpha, TIFF, WebP, GIF/APNG first frame, JPEG); the copy is always PNG. A
  format without alpha simply gives an opaque logo (MED-010-R3).
- Q: Do the flash guard, Reduce flashing and the emergency blackout apply to the logo? → A: Yes: the
  logo is a layer of the compositor visual, so the composite flash guard measures it with
  everything else and the output blackout (UIX) covers it; the logo itself is static, so it never
  adds flashes (MED-010-R5).
- Q: Do frame captures, recordings and the external display show the logo? → A: Yes, whatever the
  compositor visual outputs: REC-001 captures, REC-003 recordings and OUT-001's external display
  all show the logo when the shown visual is a compositor visual (MED-010-R5).
- Q: Does the layer inspector's solo and mute affect the logo? → A: Soloing another layer hides the
  logo while the solo lasts (CMP-012 semantics: only soloed layers show); the logo cannot itself
  be soloed or muted, because it is not an inspector layer (MED-010-R7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Put my logo on the visuals (Priority: P1)

A venue's VJ chooses their transparent PNG logo in Settings → Logo (from Photos or Files). It
appears in the bottom-right corner over the Photo, Video, Camera and Text visuals, with its soft
edges blended cleanly over whatever is behind it.

**Why this priority**: It is the observable behaviour and the import/compositing half of the
acceptance.

**Independent Test**: Import the fixture PNG (an alpha gradient and a fully transparent region): the
stored copy decodes with every alpha byte within 1/255 of the original; composited over a known
backdrop on the GPU, the result matches premultiplied "over" in linear light, transparent pixels
leave the backdrop unchanged and partial alpha shows no darkening.

**Acceptance Scenarios**:

1. **Given** no logo, **When** a transparent PNG is chosen, **Then** it is stored as PNG with its
   alpha and shown in the bottom-right corner of the compositor visuals.
2. **Given** a logo with soft edges, **When** it is shown small over a bright backdrop, **Then** its
   edges show no dark halo.
3. **Given** a file over 10 MB or over 4096 × 4096 pixels, or not an image, **When** it is chosen,
   **Then** it is refused with a notice and the previous logo stays.

---

### User Story 2 - Place and fade the logo (Priority: P1)

The VJ moves the logo to the top-left corner, makes it smaller and sets it to 60 % opacity.

**Why this priority**: A logo is only usable if it can stay out of the way.

**Independent Test**: For each corner, size and margin the logo's rectangle (in pixels) is where the
placement rule says, at portrait and landscape sizes; opacity scales the premultiplied colour.

**Acceptance Scenarios**:

1. **Given** a logo, **When** Top left, size 10 % and margin 4 % are chosen, **Then** the logo's
   longer side is 10 % of the screen's shorter side and its corner sits 4 % of the shorter side
   from the top and left edges.
2. **Given** opacity 60 %, **When** the logo is drawn, **Then** every pixel is the logo × 0.6 over the
   backdrop.

---

### User Story 3 - Keep the logo in scenes, archives and backups (Priority: P2)

The VJ exports a scene archive with the logo, imports it on another phone, and the logo comes back
with its transparency and placement. A library backup carries it; "Photos and videos" erase removes
it.

**Why this priority**: The export third of the acceptance; backups are how saved state travels.

**Independent Test**: Export a scene archive with the logo, import it into a fresh sandbox: the
logo's alpha matches the original within 1/255 and its placement is restored. Import the same
archive twice: one payload. Backup includes the logo keys; erase removes them.

**Acceptance Scenarios**:

1. **Given** a scene with a logo, **When** it is exported and imported elsewhere, **Then** the logo
   file in the archive is PNG with alpha and the imported logo matches the original.
2. **Given** a scene whose logo is not on this device, **When** it is opened or checked, **Then** the
   repair report lists the missing logo and nothing else changes.
3. **Given** "Photos and videos" erase, **When** it completes, **Then** no logo or logo setting
   remains.

### Edge Cases

- No logo: nothing is drawn; the visuals look exactly as before.
- The stored copy is missing or damaged: the logo layer is transparent and Settings shows a notice;
  the identifier is cleared when its file no longer resolves.
- A logo with no transparent pixel: stored as PNG and shown opaque.
- A very wide or tall logo: the size applies to its longer side, so it never exceeds the size
  fraction in either direction.
- Opacity 0 %: the logo is not drawn (but stays chosen).
- Custom anchor at (0, 0) or (1, 1): the logo touches the margin of that corner, never leaves the
  screen when it fits.
- The same picture as the photo or a slide: one payload; removing the photo or a slide keeps the
  logo, removing the logo keeps them.
- A scene with a malformed logo placement: the placement reads as the defaults; a logo asset with a
  non-canonical store ID is a validation error like a photo's.
- Older app versions reading a scene with a logo: the unknown asset type is kept verbatim.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-010-R1**: The user MUST be able to choose one logo image from Photos (system picker, no
  photo library permission) or Files, and remove it.
- **MED-010-R2**: The logo MUST be stored once as a FILE-008 reference in the Photos folder, named by
  `settings.logo.id`; an equal picture already stored (photo, slide, earlier logo) MUST share its
  payload. Choosing a new photo, Remove Photo, slideshow edits and reference trimming MUST NOT
  release the logo's reference; choosing a new logo or Remove Logo MUST release the previous logo's
  reference without releasing the photo's or a slide's.
- **MED-010-R3**: Import MUST go through MED-001's bounded read and MED-014's decoder, refuse files
  over 10 MB or 16,777,216 pixels, scale the copy to at most 1024 px on its longer side, and always
  write PNG with no metadata; every alpha value of the stored copy MUST be within 1/255 of the
  decoded original (at the same size).
- **MED-010-R4**: The logo MUST be drawn as premultiplied linear-light colour: the upload converts
  each texel from sRGB to linear and multiplies by alpha **before** any filtering or mipmapping, so
  sampling never mixes the colour of transparent texels into the edges; the result MUST equal
  premultiplied "over" of the logo onto the layers below within 2/255 per channel.
- **MED-010-R5**: The logo MUST be the top layer of the Photo, Video, Camera and Text visuals'
  compositors (so it appears in REC-001 captures, REC-003 recordings and OUT-001's external display,
  and passes the composite flash guard and the output blackout like every layer); it MUST NOT be drawn by
  projectM or the native spectra, and Settings MUST say which visuals show it.
- **MED-010-R6**: Placement MUST be a corner preset (top left, top right, bottom left, bottom right,
  centre) or a custom anchor (x, y in 0…1); the logo's longer side MUST be the size fraction
  (0.05…0.5, default 0.15) of the output's shorter side, keeping its aspect; the margin (0…0.2,
  default 0.04, of the shorter side) MUST separate it from the edges it is anchored to; the anchor
  point of the logo MUST land on the same fraction of the area inside the margins.
- **MED-010-R7**: Opacity (0…1, default 1) MUST multiply the logo's premultiplied colour; at 0 the
  layer draws nothing. The layer inspector (CMP-015) MUST NOT list the logo; soloing another layer
  hides the logo while the solo lasts.
- **MED-010-R8**: The logo layer MUST declare itself still (CMP-013): it is drawn again only when
  its image, placement, opacity or the picture size changes.
- **MED-010-R9**: The logo identifier and placement MUST be saved in the app's settings and restored
  after relaunch; the keys MUST be included in FILE-005 backups (the picture travels as a photo),
  removed by FILE-011's "Photos and videos" erase, listed in the UI tests' reset and in the device
  privacy check's allowed keys.
- **MED-010-R10**: Scenes MUST record the current logo as an optional asset of the new type `logo`
  (its store ID and placement), without a format version change; the logo asset MUST NOT be reported
  as unused; a logo asset whose picture is missing MUST appear in SCN-012's repair report. Opening a
  scene (launch restore, Reopen, show cue) with a logo asset whose picture resolves MUST make that
  logo and placement current; a scene without a logo asset, or with a missing picture, MUST leave
  the current logo unchanged; undo and redo MUST NOT change the logo.
- **MED-010-R11**: Scene archives (FILE-001/002) MUST carry the scene's logo as one more file
  (`assets/<key>.png`, PNG only); import MUST stage it through the logo import path, adopt it into
  the Photos folder (deduplicated by FILE-008) and make it the current logo with the scene's
  placement, all or nothing with the rest of the import; FILE-003's dry run MUST list it.
- **MED-010-R12**: Settings MUST offer a Logo section: Choose from Photos, Choose from Files, Remove
  Logo, a corner picker, size, margin and opacity sliders with ACC-005 accessible-parameter
  behaviour, help text naming the visuals that show the logo, and a non-blocking notice for refused
  imports; changes MUST be announced through the shared announcer; usable at accessibility text
  sizes.
- **MED-010-R13**: The placement maths and the premultiplication MUST be testable without a
  graphics device on every platform the packages' tests run on.
- **MED-010-R14**: DEBUG builds MUST offer a launch argument (`-uitestSeedLogo`) that seeds a
  fixture logo through the real import path, and a probe exposing whether the logo layer drew, so
  a UI test can check the overlay without the system pickers.

### Key Entities

- **Logo**: one FILE-008 reference in the Photos folder (PNG, ≤ 1024 px), named by `settings.logo.id`.
- **Logo placement**: corner (or custom), anchor, size, margin, opacity.
- **Logo layer**: the top compositor layer of a compositor visual that draws the logo at its
  placement.
- **Scene logo asset**: scene asset of type `logo` with the store ID and the placement.

## Privacy review *(Constitution, Privacy; extends MED-001's review)*

| Question | Answer |
|---|---|
| What is stored? | A sanitized PNG copy (pixels only, no metadata) of the chosen logo in the app's own folder, and two settings values (its identifier and placement). |
| Is a photo library permission needed? | No: the system picker runs out of process and hands over a copy. |
| Is anything sent or analysed? | No. |
| Where can the logo go? | Into the user's own scene archives (FILE-001), library backups (FILE-005) and the device backup, like the MED-001 photo. |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: the review passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-010-S1** (the acceptance, import): the fixture PNG (64 × 64, a horizontal alpha gradient
  0…255 and a fully transparent region) imported as a logo decodes from the stored copy with every
  alpha byte within 1/255 of the original and the transparent region at alpha 0.
- **MED-010-S2** (the acceptance, compositing): the fixture logo composited over a known opaque
  backdrop on the GPU matches premultiplied "over" in linear light within 2/255 per channel; pixels
  under the transparent region equal the backdrop within 1/255; no pixel at partial alpha is darker
  than both the backdrop and the logo colour (no dark fringe), also when the logo is drawn at a
  quarter of its size.
- **MED-010-S3** (the acceptance, scene export): a scene archive exported with the logo and imported
  into a fresh sandbox gives a current logo whose decoded alpha matches the original within 1/255
  and whose placement equals the exported one.
- **MED-010-S4**: For every corner preset at 390 × 844 and 844 × 390, the logo's rectangle matches
  the placement rule within 1 pixel.
- **MED-010-S5**: Importing the same logo twice, or importing an archive whose logo equals the stored
  photo, leaves one payload; Remove Photo keeps the logo.
- **MED-010-S6**: The logo keys are included in backups and removed by "Photos and videos" erase.
- **MED-010-S7**: In a DEBUG UI test on the simulator with the seeded logo and the Text visual, the
  probe reports the logo drawn within 30 seconds of test time.
- **MED-010-S8** (device stage): on D1, a transparent PNG chosen in the real Photos picker and one
  from Files appear over the Photo visual with clean edges.

## Assumptions

- One logo at a time (like the one stored photo); scenes record the current logo and its placement.
- Animated logos (APNG, GIF) show their first frame (MED-008 covers animation).
- A logo on projectM and the native spectra needs those visuals on a compositor; that is a later
  row.
- Device picker behaviour (MED-010-S8) is verified only in the final device stage.
