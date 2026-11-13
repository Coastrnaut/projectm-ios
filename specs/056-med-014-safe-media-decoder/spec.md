# Feature Specification: MED-014 Safe Media Decoder

**Feature Branch**: `feature/med-014` (spec directory `056-med-014-safe-media-decoder`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (MED-014-T01-T22 verified on the Mac: host, Linux shape and iOS 27.2 simulator; device task T23 `{device}` open)

**Input**: User description: "Implement MED-014 (Safe media decoder) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Reject malformed or oversized
files with recoverable errors." Acceptance, verbatim: "Corrupt fixture fails gracefully and leaves
compositor running." Verification: simulator fixture media, plus a device task with real HEIC,
ProRAW, panorama and HDR files on D1/D3. Depends on MED-001 (integrated: the photo layer and its
`ImageDecoding` seam, ADR-0020) and MED-002 (the video layer and its `VideoFrameReading` seam,
ADR-0022). Known findings to fix: ImageIO decodes a truncated PNG without error (MED-001 research
D5, test `testDamagedImagesAreRefused`), and the priority-inversion notice from synchronous
AVFoundation / file-coordination calls during video import (docs/test-reports/video-layer.md)."

Identifiers in this feature carry the roadmap ID: requirements `MED-014-R1…`, success criteria
`MED-014-S1…`, tasks `MED-014-T01…`. Other features' IDs are cited as they are: MED-001-R5, R11, R12,
R14 (photo import limits, notice, decoder seam, stored copy), MED-002-R5, R14, R15, R18 (video import
checks, notice, reader seam, stored copy), CMP-001-R3 (a failing layer shows its fallback and never
stops the frame).

## Baseline: what exists today (audit of 2026-11-13, commit `36651be`)

The row's gap status is "Gap candidate". The audit confirms a partial gap.

| Area | Today | Gap for this row |
|---|---|---|
| Image import | `ImageIODecoder`: size limit, ImageIO type, ImageIO status, pixel count from ImageIO's properties, a bounded thumbnail decode at most 4096 px. | No structural check of its own: a PNG cut short (every cut point after the first rows) decodes "complete" with blank rows and is imported. ImageIO parses the header of an absurd picture before the pixel limit is checked. |
| Video import | `VideoProbe`: file size, AVFoundation tracks, codec, size, frame rate, then the first picture through `AVAssetReader` (synchronous `copyNextSampleBuffer`). | No container check before AVFoundation opens the file; the synchronous first-picture read and the coordinated copy block a user-initiated thread on lower-priority system work (the Thread Performance Checker's priority-inversion notice). |
| Layers at load time | The photo layer decodes the stored copy through the same decoder; the video reader re-loads tracks. A failure sets `.failed`, the layer draws its transparent fallback and the app shows "couldn't be loaded". | Not proven with corrupt stored files in a running compositor with other layers; the video reader does no container check before reopening. |
| Fixtures | MED-001/002 tests generate valid files plus half a JPEG, a zero-size PNG, text and an audio-only file. | No corpus of malformed files, no fuzzing. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which image formats get a structural check of their own, and what happens to the others (GIF, TIFF/DNG/ProRAW, WebP, BMP…)? → A: PNG, JPEG and HEIF/AVIF (the formats the Photos picker and Files deliver almost always) are checked structurally before ImageIO sees them. Other formats ImageIO recognizes keep MED-001's checks (ImageIO's type, status and pixel count, then the bounded thumbnail decode); refusing them would take away working imports (ProRAW DNG is TIFF). A file whose first bytes match none of the known signatures still goes to ImageIO, which decides "not an image".
- Q: Is a JPEG with no end marker (EOI) refused, though some old cameras wrote them? → A: Refused as damaged. A missing end marker is how a JPEG cut short looks, and a cut file decodes with grey or blank rows; the notice tells the user it "may be damaged". Bytes after the end marker (some cameras append data) are accepted and ignored.
- Q: Which PNG chunks have their checksum verified? → A: Every critical chunk (IHDR, PLTE, IDAT, IEND: the ones that define the picture). Ancillary chunks (text, color profile, APNG frames) are skipped by length without their checksum, as the PNG specification allows decoders to do; the sanitized copy never carries them anyway.
- Q: How is the work of a malformed file bounded without a wall-clock timeout? → A: By counts and sizes taken from the file and checked against its length before anything is allocated: every box or chunk length must fit in the bytes that remain; a video container walk visits at most 4,096 box headers and nests at most 8 levels; only the first sample description of a track is read and no sample table is read at all; an image is decoded only as a thumbnail at the stored size (≤ 4096 px); a video's first picture is decoded at most 256 px long. No timer ever decides an outcome.
- Q: Does the stored-copy load (relaunch, choosing the visual again) run the same checks as the import? → A: Yes. The photo layer decodes through the same hardened decoder and the video reader checks the container before every open (start, loop, seek), so a stored file that is damaged later fails as a typed error, the layer draws transparent with the existing "couldn't be loaded" notice, and every other layer and the compositor keep running (CMP-001-R3).
- Q: After a video fails mid-playback (a read error or a failed reopen at a loop), does the layer retry? → A: No. It stays failed (transparent, notice shown once) until its content changes or the visual is chosen again; a retry loop on a broken file would spend decode work and repeat the notice. Choosing the visual again or relaunching re-checks the file.
- Q: Which size does a HEIF header check use when the file holds several pictures (the main image, its grid tiles, a thumbnail, a depth map)? → A: The largest width and the largest height among the image-size properties (`ispe`) found, checked against the pixel limit. It can only over-estimate the main picture (the grid's own size property is the full picture), never let a larger one through; ImageIO's own size check of the first picture follows as before.
- Q: Is anything logged or counted when a file is refused? → A: No new logging: the typed error is the layer's state and the existing notice, as for MED-001/002. Refused bytes are never logged (they are user content); the tests read the typed results.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A damaged or hostile image is refused with a clear notice (Priority: P1) — MVP

A viewer picks a photo that was cut short by an interrupted download (or a file that only pretends
to be a photo). The app refuses it with the photo notice ("That image couldn't be read. It may be
damaged."), keeps the photo that was already stored, and the visualization never stops.

**Why this priority**: It is the row's observable behavior and the known MED-001 gap (truncated PNG).

**Independent Test**: The fixture table (US3) run through the image decoder: each malformed file
gives its exact typed error; the valid control decodes.

**Acceptance Scenarios**:

1. **Given** a PNG cut at any point after its signature, **When** it is imported, **Then** it is refused as damaged and nothing is stored.
2. **Given** a PNG whose header claims 100,000 × 100,000 pixels, **When** it is imported, **Then** it is refused as "more than 100 million pixels" before any pixel is decoded.
3. **Given** a JPEG without its end marker or with an impossible frame header, **When** it is imported, **Then** it is refused (damaged, or too many pixels when the header's size is over the limit).
4. **Given** an empty file, **When** it is imported, **Then** it is refused as "not an image".

---

### User Story 2 - A damaged or hostile video is refused with a clear notice (Priority: P1)

A viewer picks a movie whose index points past the end of the file, or a sound-only movie. The app
refuses it with the video notice before the system's media framework decodes anything, and the stored
video and the visualization are unaffected.

**Why this priority**: Same row, the video half; a container index is where a malformed movie asks
for unbounded work.

**Independent Test**: The video fixtures through the container check and the import probe.

**Acceptance Scenarios**:

1. **Given** a movie whose `moov` box claims more bytes than the file has, **When** it is imported, **Then** it is refused as damaged.
2. **Given** a movie with no video track, **When** it is imported, **Then** it is refused as "not a video".
3. **Given** a valid small H.264 movie, **When** it is imported, **Then** it is accepted exactly as before (MED-002 unchanged).

---

### User Story 3 - Every malformed file gives a typed result, never a crash or a hang (Priority: P1)

The decoder is fed a corpus of known-bad files and thousands of random mutations of valid ones. Each
one returns either a decoded picture or one of the existing typed errors; none crashes, none reads
outside the data, none allocates more than its limits allow, none loops.

**Why this priority**: The guarantee behind "recoverable errors".

**Independent Test**: Fixture table and fixed-seed mutation fuzz in the package tests (each run under
a second of work on the Mac).

**Acceptance Scenarios**:

1. **Given** the fixture corpus, **When** each fixture is checked, **Then** the outcome equals the table in the plan exactly.
2. **Given** a fixed seed and valid tiny PNG, JPEG, HEIF and movie headers, **When** bytes are flipped, cut, duplicated or overwritten, **Then** every mutation returns a typed result.

---

### User Story 4 - A stored file that breaks later does not stop the show (Priority: P1)

A stored photo or video becomes unreadable (damaged on disk, replaced, deleted). When the visual
loads it (launch, choosing the visual, a video loop), that layer turns transparent, the notice says
the photo or video couldn't be loaded, and every other layer and the compositor keep drawing frames.

**Why this priority**: The row's acceptance: "Corrupt fixture fails gracefully and leaves compositor
running."

**Independent Test**: A running compositor with a photo layer, a video layer and a plain test layer;
the stored files are replaced by corrupt fixtures; frames keep coming, the broken layers report their
typed failure and are transparent, the test layer's pixels are unchanged. In the app, a DEBUG seed of
a corrupt photo and video shows the notices and the app stays usable.

**Acceptance Scenarios**:

1. **Given** a photo layer whose stored file is replaced by a truncated PNG, **When** it reloads, **Then** its state is failed (damaged), it draws its transparent fallback, and the frame count keeps increasing.
2. **Given** a playing video whose stored file is replaced by a damaged movie, **When** the reader reopens it, **Then** its state is failed (damaged) and the compositor keeps drawing the other layers.
3. **Given** the app launched with a corrupt seeded photo and video, **When** the import runs, **Then** the notices appear, nothing is stored, and Settings and the visualizer still respond.

---

### User Story 5 - Importing a video does not block a high-priority thread on low-priority work (Priority: P2)

Importing a picked video no longer makes the Thread Performance Checker report a priority inversion
caused by the import's own calls.

**Why this priority**: A known MED-002 finding; it can cause stutter while importing on a device.

**Independent Test**: The video store tests and the video UI test run with the checker; their logs no
longer show the inversion notice attributed to the import path (or the remaining source is recorded).

**Acceptance Scenarios**:

1. **Given** a video import in the tests, **When** it runs, **Then** the first-picture check and the picked-file copy do not block a user-initiated thread on lower-priority work.

### Edge Cases

- A file exactly at a limit (40 MB, 100 million pixels, 4096 px, 500 MB) is accepted; one byte or pixel more is refused (unchanged from MED-001/002).
- A PNG with junk after IEND, a JPEG with data after EOI: accepted (common in camera files).
- An animated PNG: accepted (first picture, as MED-001); its frame chunks are ancillary.
- A 64-bit box size (`size == 1`) and a last box running to the end of the file (`size == 0`): accepted when they fit.
- A movie with the index (`moov`) after the media data (`mdat`): accepted.
- A HEIF whose `ftyp` box is cut or whose brands are not legible: refused as damaged. Legible brands without an image brand (an MP4 picked as a photo) go to ImageIO, which refuses it as "not an image".
- Random bytes that start with a PNG signature: refused as damaged (not "not an image": they claim to be one).
- A file removed between launch and load: the existing "couldn't be loaded" path (unreadable).

## Requirements *(mandatory)*

### Functional Requirements

- **MED-014-R1**: Before an image is handed to the system decoder, its first bytes MUST be identified as PNG, JPEG, HEIF/AVIF or other; PNG, JPEG and HEIF MUST pass a structural check of their own (R2-R4).
- **MED-014-R2**: A PNG MUST start with the PNG signature and an IHDR chunk with valid fields (non-zero size, a legal bit depth and color type pair, compression 0, filter 0, interlace 0 or 1); every chunk length MUST fit in the remaining bytes; each critical chunk's checksum MUST match; at least one IDAT and an IEND MUST be present. Failures are `.damaged`.
- **MED-014-R3**: A JPEG MUST start with SOI, have a frame header (SOF) with non-zero size and 1-4 components before the first scan, have every segment length fit, and end with EOI. Failures are `.damaged`.
- **MED-014-R4**: A HEIF/AVIF MUST start with an `ftyp` box naming an image brand, every top-level box MUST fit in the file, and a `meta` box MUST be present; the largest image size found in its item properties is its header size. Failures are `.damaged`.
- **MED-014-R5**: When the header gives a size, the pixel limit (100 million) MUST be checked from it before any decode (`.tooManyPixels`); the system decoder's own size check stays as a second check. For HEIF the header size is the largest `ispe` width and height found.
- **MED-014-R6**: An image MUST be decoded only as a bounded thumbnail at the stored size (≤ 4096 px on its longest side), never at full size first.
- **MED-014-R7**: Before AVFoundation opens a movie (import and every reader open), its container MUST be checked: top-level boxes walked with every size fitting the file (`size 1` 64-bit and `size 0` to-end-of-file handled), at most 4,096 box headers and 8 levels; exactly one `moov`; inside it, tracks found by their handler, and for the first video track the first sample description's codec and coded size read. No sample table is read.
- **MED-014-R8**: Container outcomes: not a recognizable container → `.notAVideo`; a box that does not fit, a missing or duplicated `moov`, or nesting/box count over the bound → `.damaged`; no video track → `.notAVideo`; a coded size over 4096 px → `.pictureTooLarge`. AVFoundation's checks (MED-002-R5) still follow.
- **MED-014-R9**: The import's first-picture check MUST use the system's asynchronous image generation with a maximum size of 256 px (one picture, bounded memory), not a blocking sample read on the importing thread.
- **MED-014-R10**: The import path MUST NOT block a user-initiated thread on lower-priority work as reported by the Thread Performance Checker; each suspected call (first-picture read, coordinated file read) MUST be investigated, changed only when it is a source, and the finding and its resolution recorded in the test report and ADR-0022.
- **MED-014-R11**: Every decode failure MUST surface as one of the existing typed errors (`ImageImportError`, `VideoImportError`); no new user-visible messages are added. The import refuses with the existing notice and keeps the stored copy (MED-001-R11, MED-002-R14).
- **MED-014-R12**: A layer whose stored file fails at load (photo) or at any reader open or read (video) MUST report `.failed(<typed error>)`, draw its transparent fallback, and MUST NOT stop the compositor or affect other layers (CMP-001-R3); the app shows the existing "couldn't be loaded" notice. A failed video layer does not retry until its content changes or the visual is chosen again; nothing new is logged.
- **MED-014-R13**: The structural checks MUST be plain Swift (no ImageIO, AVFoundation or Metal) so they build and are tested on Linux, and MUST never read outside the given bytes or allocate in proportion to a length field.
- **MED-014-R14**: The tests MUST generate their fixtures (no media checked in) and include the corpus of US3 and a fixed-seed mutation fuzz; a DEBUG `corrupt` variant of the photo and video UI-test seeds MUST exist.

### Key Entities

- **Media header facts**: the format found, and when the header states them the picture size (image) or, for a movie, whether it has a video track, its codec code and coded size.
- **Sniff failure**: why the bytes are not a well-formed file of their format (not recognized, truncated, corrupt, over the walk bound); mapped to the existing typed import errors.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-014-S1**: 100 % of the fixture corpus (at least 14 files: truncated PNGs at several cut points, PNG with a bad checksum, PNG with a 100,000 × 100,000 header, JPEG without EOI, JPEG with an absurd frame header, zero-byte file, random bytes with a PNG signature, HEIF with a damaged `ftyp`, movie whose `moov` overruns the file, movie with no video track, and valid image and movie controls) gives exactly its expected outcome.
- **MED-014-S2**: A fixed-seed fuzz of at least 2,000 mutations over valid tiny files finishes with a typed result for every mutation and no crash, in under 1 second of test time on the Mac.
- **MED-014-S3**: With a corrupt photo and a corrupt video in a running compositor, frames keep being produced (the frame count increases on every frame), the two layers report their typed failure and are transparent, and a third layer's pixels are unchanged.
- **MED-014-S4**: In the app, a corrupt seeded photo and video show their notices within 10 s and Settings opens and closes normally afterwards.
- **MED-014-S5**: Valid imports behave exactly as before: every MED-001 and MED-002 test still passes.
- **MED-014-S6**: The video import's priority-inversion notice is gone from the test logs, or its remaining source is identified and recorded.

## Assumptions

- The import limits stay MED-001's and MED-002's (40 MB, 100 million pixels, 4096 px stored; 500 MB, 4096 px, 60.5 fps); this row adds checks, not new limits.
- Decoding inside ImageIO and VideoToolbox remains the system's; structural checks reduce what reaches them, they cannot prove the system decoder safe. Hostile files that pass the structure checks are bounded by the thumbnail size and by the one-picture probe.
- Real HEIC, ProRAW, panorama and HDR files are checked on D1/D3 by a `{device}` task; the simulator results are not device evidence (Constitution X).
- Text (MED-009) decodes no files and the generator-graph importer (SHD-011) is already bounded; both are out of scope.
