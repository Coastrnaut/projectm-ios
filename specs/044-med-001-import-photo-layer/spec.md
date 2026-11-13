# Feature Specification: MED-001 Import Photo Layer

**Feature Branch**: `feature/med-001` (spec directory `044-med-001-import-photo-layer`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (MED-001-T01-T21 verified on the Mac: host, Linux shape and iOS 27.2 simulator; device tasks T22-T24 `{device}` open)

**Input**: User description: "Implement MED-001 (Import photo layer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Choose an image from Photos or
Files without uploading it." Acceptance, verbatim: "Selected image renders after relaunch when
copied into app storage." Depends on CMP-001 (integrated: Packages/Compositor, ADR-0013) and builds
its stack through CMP-002's `LayerStack`. Leave room for MED-006 (slideshow), MED-007 (Ken Burns),
MED-008 (animated images), MED-010 (logo overlay), MED-013 (relinking) and MED-014 (safe media
decoder, P0, depends on this row); implement only MED-001."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MED-001-R1…`, success criteria `MED-001-S1…`, tasks `MED-001-T01…`. Requirements
of other features are cited by their own IDs: CMP-001-R1 to R11 (the layer contract), CMP-002-R1
(stack order), CAM-001-R7 (a visual's frame loop runs only while shown), AUD-001-R2 (imported files
live in Application Support), FR-065 (what the app may store), FR-068 (no networking).

The photo is user content brought into the app; the constitution's Privacy section asks for a
privacy review of any new kind of stored user data. This specification's "Privacy review" section
is that review.

## Baseline: what exists today (audit of 2026-11-13, commit `1eded3a`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Image import | Nothing in the app or packages imports, decodes or stores images (no Photos picker, no image document picker, no ImageIO use). AUD-001 imports audio files from Files into Application Support. | No way to bring a picture into the app. |
| Layers | CMP-001's compositor draws layers; the camera (CAM-001) is the one picture-producing layer, under the circular spectrum, built through CMP-002's `LayerStack`. | No layer shows a still image. |
| App | Settings › Visual offers projectM, Circular Spectrum, Linear Spectrum and Camera (session only). | No photo visual, no stored image, no remove action. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: How is metadata removed from the stored copy: keep the original file and never read its metadata, or re-encode the pixels? → A: Re-encode. The picture is decoded upright (the orientation is applied while decoding, so no orientation tag is needed), scaled to at most 4096 px, and written as a new file with no metadata dictionaries: PNG when the picture has transparency (lossless, alpha kept for MED-010), otherwise JPEG at quality 0.9 (a 4096 px photo stays around 2-4 MB instead of about 25 MB as PNG; the loss is invisible full screen). Rejected: storing the original (its EXIF/GPS would sit in the container and in backups even if never read) and HEIC output (the encoder is not available on every simulator and older device).
- Q: Does the photo fill the screen (cropping) or fit inside it (letterboxing)? → A: Fill by default, cropping the overflow equally on both sides, like the Camera visual (a background with black bars looks broken behind a spectrum). The layer also implements fit, with transparent bars, for later rows (MED-007, MED-010); this row offers no switch.
- Q: Is the stored copy excluded from device backups? → A: No. It is included, like imported audio (AUD-001) and the preset copies: it is the viewer's own content, backups are the viewer's own and Apple's, and excluding it would lose the photo on a device restore. The privacy policy says so.
- Q: Which limits apply to a picked image? → A: At most 40 MB per picked file and 100 million pixels per picture (a 63-megapixel iPhone panorama fits; decoding a larger picture risks the memory limit on D1), and the stored copy at most 4096 px on its longest side (sharper than any supported display, at most 64 MB of GPU memory). MED-014 may tighten or add checks behind the same decoder boundary.
- Q: Is the Photo choice remembered after a relaunch, and what if its stored copy cannot be used? → A: Remembered (no sensor is involved, so CAM-001-R11's reason does not apply; it is the acceptance). A missing copy or an invalid identifier reads as "no photo" and the identifier is cleared; a copy that exists but cannot be decoded keeps its identifier, shows the transparent fallback with the notice "The photo couldn't be loaded", and Remove Photo deletes it. Relinking is MED-013.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose a photo and see it behind the music (Priority: P1) — MVP

A viewer opens Settings, chooses the "Photo" visual, taps "Choose from Photos…" (or "Choose from
Files…"), and picks one image. The app copies the image into its own storage and shows it full
screen behind the circular spectrum. The original is never uploaded and the app gets no access to
the rest of the library.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: A test-only launch flag puts a fixture image through the same import path
(system pickers cannot be automated); choose Photo; the photo layer reports the image's size and
counts frames that showed it.

**Acceptance Scenarios**:

1. **Given** the Photo visual with no photo, **When** the viewer picks an image, **Then** the image
   appears behind the spectrum and Settings shows its size and a "Remove Photo" button.
2. **Given** a picked image with location and camera metadata, **When** it is imported, **Then** the
   stored copy holds the upright pixels only, with no location, camera or other metadata.
3. **Given** the Photos picker, **When** it is shown, **Then** iOS asks for no photo library
   permission (the picker runs outside the app and returns only the chosen image).

---

### User Story 2 - The photo is still there after relaunch (Priority: P1)

The viewer closes the app and opens it again. The Photo visual and its image come back.

**Why this priority**: It is the row's acceptance.

**Independent Test**: The UI test seeds a fixture, shows it, terminates the app, relaunches it
without the seed flag, and the photo layer reports the same image again.

**Acceptance Scenarios**:

1. **Given** an imported photo shown in the Photo visual, **When** the app is terminated and opened
   again and the visualizer starts, **Then** the same stored copy renders.
2. **Given** the stored copy has gone missing, **When** the app opens, **Then** the Photo visual
   shows the spectrum over black and Settings says no photo is chosen.

---

### User Story 3 - Remove the photo (Priority: P1)

The viewer taps "Remove Photo". The copy is deleted from the app's storage and the visual returns to
the spectrum over black.

**Why this priority**: Privacy: the viewer must be able to delete what they brought in.

**Independent Test**: Unit test: remove deletes the file and the stored identifier. UI test: Remove
Photo returns the photo layer to "No photo".

**Acceptance Scenarios**:

1. **Given** an imported photo, **When** the viewer taps Remove Photo, **Then** the stored copy no
   longer exists, the next frame shows no photo, and a relaunch shows no photo.

---

### User Story 4 - Bad files never break the app (Priority: P2)

The viewer picks something that cannot be used: a file that is not an image, a damaged image, a
file over the size limit or a picture with too many pixels. A short notice explains it; the
visual keeps running and the previous photo, if any, stays.

**Why this priority**: The acceptance of MED-014 builds on it; a crash or a frozen visual is worse
than no photo.

**Independent Test**: Package tests feed corrupt, oversized and non-image data to the importer and
the decoder and expect typed errors; an app unit test checks the notice text and that the stored
photo is unchanged.

**Acceptance Scenarios**:

1. **Given** a stored photo, **When** a corrupt file is picked, **Then** a notice says the image
   could not be read and the stored photo is unchanged.
2. **Given** any refused file, **When** the notice is shown, **Then** it does not block the screen
   and disappears on its own or when dismissed.

### Edge Cases

- The viewer cancels a picker: nothing changes, no notice.
- A picked image is larger than the stored size: it is scaled down (aspect kept) when copied.
- A panorama with a very wide aspect ratio: kept within the pixel limits; aspect fill shows its
  middle, cropping the sides.
- An image in a wide color space (Display P3): converted to the app's working color space; colors
  outside it are clipped.
- An image with transparency (PNG): transparency is kept; what is transparent shows black behind
  it in the Photo visual.
- An animated image (GIF, animated HEIC/PNG): its first frame is imported as a still (MED-008
  covers animation).
- A Live Photo or a burst: the still image is imported.
- An iCloud Photos item not on the device: the picker downloads it out of process; if that fails,
  the notice says the image could not be read.
- An image orientation tag (portrait photo stored sideways): the copy is stored upright, so no
  orientation tag is needed afterwards.
- Storage is full when copying: the notice says the photo could not be saved; the previous photo
  stays.
- Importing a second photo: it replaces the first, whose copy is deleted once the new one is saved.
- The stored copy is corrupt at launch: the layer shows nothing (transparent), a notice says the
  photo could not be loaded, Remove Photo still works.
- The stored identifier is not a valid identifier or names a path outside the photo folder: it is
  ignored (no photo) and never opened.
- The visual is left while the image is still decoding: the result is dropped.
- The output size changes (rotation): the image is not decoded again; only the geometry changes.
- No Metal device: the Photo visual falls back to projectM with the same notice as the other
  native visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-001-R1**: Settings MUST offer a "Photo" visual beside projectM, Circular Spectrum, Linear
  Spectrum and Camera. It shows the photo layer at the bottom with the circular spectrum layer over
  it, built as a layer stack (CMP-002-R1: index 0 bottom).
- **MED-001-R2**: While Photo is chosen, Settings MUST offer "Choose from Photos…" (the system Photos
  picker, images only, one image) and "Choose from Files…" (the system document picker, image
  types only, one file). The Photos picker MUST be the out-of-process system picker that needs no
  photo library permission; the app MUST NOT request photo library access or declare a photo
  library usage description.
- **MED-001-R3**: A picked image MUST be copied into the app's own storage before it is used; the
  layer MUST read only that copy. Nothing about the original (its location, its library
  identifier, its file name) is kept after the import.
- **MED-001-R4**: The stored copy MUST contain only the image's pixels, made upright: no location,
  camera, date, maker or other metadata, re-encoded as PNG when the picture has transparency and as
  JPEG (quality 0.9) otherwise. The app MUST NOT show or store the original's metadata.
- **MED-001-R5**: Imports MUST be refused, with a typed reason, when the picked file is larger than
  40 MB, when its picture has more than 100 million pixels, when it is not an image the system can
  decode, or when it is damaged. A picture longer than 4096 pixels on its longest side MUST be
  scaled down (aspect kept) to 4096 when copied.
- **MED-001-R6**: The app MUST keep one photo at a time. Its identifier MUST be stored in the app's
  settings; a new import replaces the previous photo, whose copy is deleted only after the new copy
  is saved. A failed import MUST leave the previous photo and identifier unchanged.
- **MED-001-R7**: "Remove Photo" MUST delete the stored copy and the identifier; the photo layer
  then shows nothing from the next frame on.
- **MED-001-R8**: The Photo visual choice MUST persist across launches (no sensor is involved,
  unlike Camera, CAM-001-R11). After a relaunch the stored copy MUST render without any new choice
  (the row's acceptance).
- **MED-001-R9**: The photo layer MUST follow the CMP-001 layer contract: the whole picture per frame
  in linear light, premultiplied alpha, from the display-encoded image (sRGB to linear), scaled to
  fill the output keeping its aspect ratio and cropping the overflow equally (fill is the default;
  fit, letterboxed with transparency, is available to later rows).
- **MED-001-R10**: The image MUST be decoded once per stored copy, off the frame loop; until it is
  ready, or when it fails, the layer MUST show its transparent fallback (never a stall). Per frame
  the layer MUST NOT allocate, wait on a lock without bound or do I/O.
- **MED-001-R11**: Every refused import, a failed save and an unreadable stored copy MUST show a
  non-blocking notice naming the reason in plain words; the visual and the audio source keep
  running and nothing is restarted.
- **MED-001-R12**: Image decoding and the import's checks MUST sit behind one replaceable decoder
  boundary with typed errors, so MED-014 (safe media decoder) can harden it without changing the
  layer or the app.
- **MED-001-R13**: The import and the photo MUST stay on the device: no upload, no network use
  (FR-068). The copy lives in the app's Application Support folder (like AUD-001-R2) and, like other
  app data, is included in the user's own device backups.
- **MED-001-R14**: A stored identifier MUST resolve only to a file inside the app's photo folder; an
  invalid identifier or a missing file reads as "no photo" and is cleared. A copy that exists but
  cannot be decoded keeps its identifier, shows the transparent fallback and the notice, and can be
  removed.
- **MED-001-R15**: VoiceOver MUST name the visual ("Photo visualization") and its state (no photo,
  loading, shown with its size, could not be loaded); the Settings buttons MUST be labeled.
- **MED-001-R16**: The flows MUST be testable without the system pickers: a debug-only launch flag
  imports a generated fixture through the same import path; it MUST NOT exist in Release builds.
- **MED-001-R17**: The privacy policy and the App Privacy notes MUST describe imported photos: copied
  into the app on the device, metadata removed, never sent, removable in the app, deleted with the
  app; the App Privacy answer stays "Data Not Collected".
- **MED-001-R18**: The size, geometry and error types MUST build on every host including Linux; only
  decoding (ImageIO) and drawing (Metal) compile out there.

### Key Entities

- **Stored photo**: the app's one imported image: an identifier, the stored copy (pixels only,
  upright, at most 4096 px on its longest side), its pixel size and whether it has transparency.
- **Import limits**: 40 MB per picked file, 100 million pixels per picture, 4096 px stored longest
  side.
- **Import error**: not an image, too large, too many pixels, damaged, could not be read, could not
  be saved.
- **Photo layer**: a CMP-001 layer drawing the decoded stored copy (aspect fill), or throwing "not
  ready" so the compositor shows its transparent fallback; its state is empty, loading, ready
  (size) or failed (reason).

## Privacy review *(mandatory for new stored user data — Constitution, Privacy)*

| Question | Answer |
|---|---|
| What is accessed? | Only the one image the viewer picks, through the system Photos picker (out of process; no library permission) or the system Files picker (one file, read once). |
| When? | Only after the viewer taps Choose from Photos… or Choose from Files…; nothing at launch. |
| What is stored? | One copy of the picked image, re-encoded with its pixels only (upright, no location, camera, date or other metadata), and its identifier in the app's settings (R3, R4, R6). No thumbnail, history or original file name. |
| Where, and for how long? | In the app's Application Support folder on the device until the viewer taps Remove Photo, imports another photo, or deletes the app. Included in the viewer's own device backups like other app data (R13). |
| Is anything sent? | No. No upload, no network use (FR-068); the pickers are Apple's and return the file to the app on the device. |
| Is anything analysed? | No. The pixels are only scaled and drawn; no face, text or scene detection. |
| What if the viewer refuses? | Nothing changes: no permission exists to refuse; cancelling a picker leaves the app as it was. |
| App Store privacy label | Unchanged: Data Not Collected (data kept only on the device is not collected). The owner confirms the answers in App Store Connect; this feature only documents them. |

Result: no collection, no transmission, no new permission; the only new stored data is the
viewer's chosen photo, stripped of metadata and removable in the app. The review passes, conditional
on R2 to R7 and R13 being verified (MED-001-S2 to S5) and on the device tasks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-001-S1**: A picked image renders behind the spectrum: a solid fixture color reads back
  within 2/255 of its linear value in a 64 × 64 layer picture, and the count of frames that showed
  the photo grows while the visual is on screen.
- **MED-001-S2**: After a relaunch, the same stored copy renders with no new choice (UI test: seed,
  show, terminate, relaunch, shown again with the same size).
- **MED-001-S3**: A stored copy made from a fixture with location and camera metadata has no
  location (GPS), TIFF, IPTC, maker or XMP camera properties when read back, its EXIF holds only
  the copy's own pixel size and color space (written by the system encoder), and none of the
  original's values appear anywhere in the stored bytes.
- **MED-001-S4**: Remove Photo deletes the copy (the file no longer exists) and the identifier; the
  next frame shows no photo.
- **MED-001-S5**: 100 % of corrupt, oversized, too-many-pixel and non-image fixtures are refused
  with their typed reason; the previous photo is unchanged and the visual keeps running.
- **MED-001-S6**: The compliance check passes, the app declares no photo library usage description,
  and the built app's privacy manifest check finds no undeclared required-reason API.

## Assumptions

- One photo at a time is enough for this row; several images and their order belong to MED-006
  (slideshow), placement and pan/zoom to MED-007, animation to MED-008, reusable logo assets with
  alpha to MED-010, missing-asset relinking to MED-013, and the hardened decoder to MED-014.
- A stored copy at most 4096 px on its longest side is sharp on every supported display (the
  largest drawable, iPad Pro 13", is 2752 × 2064) while bounding memory.
- The layer's opacity, blend and transform are CMP-003 to CMP-005; this row composites at the
  identity values.
- Device behaviour (the real Photos picker with limited and full library access, Files and iCloud
  Drive, HEIC and large panoramas on D1 and D3) is verified only in the device stage, by the owner,
  because system pickers cannot be automated.
