# Feature Specification: AUD-002 Support common audio containers

**Feature Branch**: `feature/aud-002` (spec directory `006-aud-002-support-common-audio-containers`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement AUD-002 (Support common audio containers) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Decode compatible MP3, AAC, M4A,
WAV and AIFF with clear unsupported-format errors." Acceptance, verbatim: "Five fixture formats
decode; corrupt files produce recoverable errors." Dependencies: AUD-001 (integrated). Honor the
repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `AUD-002-R1…`, success criteria `AUD-002-S1…`, tasks `AUD-002-T01…`. Requirements
of feature 001 (`specs/001-ios-projectm-visualizer/spec.md`) and of AUD-001
(`specs/003-aud-001-import-drm-free-audio-files/spec.md`) stay in force unless a line below amends
one explicitly.

## Baseline: what AUD-001 already delivers (audit of 2026-11-12)

AUD-001 built the imported-audio library and plays its tracks as In-App Playback. It accepts "a
file whose type the system identifies as audio and that the system's audio decoder can open" and
left the per-format guarantee to this feature. Audited on the build Mac, with generated files:

| Format | Import and playback in AUD-001 | Tested in AUD-001 |
|---|---|---|
| WAV | Works when the file is named as a WAV | Yes (16-bit, 44.1 and 48 kHz) |
| AIFF | Works when named as AIFF | No |
| M4A (AAC) | Works when named as M4A | No |
| AAC (raw `.aac`) | Works when named as AAC | No |
| MP3 | Works when named as MP3 | No |

Gaps found:

1. **The file's name decides how it is read.** A WAV or AIFF file named `.mp3` is refused as
   damaged although it is intact, and a raw AAC file named `.mp3` is accepted as a different,
   wrong kind of audio that then cannot be played.
2. **One message for four different problems.** A text file named `.wav`, a damaged file, a file
   with no audio in it, and a file in an encoding the device cannot decode all produce "This audio
   file can't be read. It may be damaged."
3. **Truncated files can enter the library.** Only the beginning of a file is checked, so an AIFF
   or M4A file cut off part-way is accepted and then plays silence or stops early.
4. **A stored copy that stops decoding is not noticed at play time** as long as its header still
   opens; playback starts and is silent instead of reporting "In-App Playback failed".
5. **No test** covers MP3, AAC, M4A or AIFF, mono and stereo together, or sample rates other than
   44.1 and 48 kHz, through import and playback.

This feature closes those gaps and nothing else.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - My MP3, AAC, M4A, WAV and AIFF files all play (Priority: P1)

A user imports audio files in the five common formats, in mono or stereo and at the usual sample
rates. Every one appears in "Your Audio" with the right duration, and tapping it plays it at the
right pitch and speed through In-App Playback, with the visualizer reacting.

**Why this priority**: This is the roadmap row's observable behavior and the first half of its
acceptance check. Without a per-format guarantee, "Import Audio…" is a gamble for the user.

**Independent Test**: Import one generated tone in each of the five formats and play each; every
one reaches "Active audio" and sounds at the generated pitch.

**Acceptance Scenarios**:

1. **Given** a valid MP3, raw AAC, M4A, WAV or AIFF file, **When** the user imports it, **Then**
   it is listed with its duration, sample rate and channel count as the file states them.
2. **Given** an imported track in any of the five formats, **When** the user plays it, **Then**
   non-silent audio reaches the visualizer and the output, labeled "In-App Playback".
3. **Given** a track whose sample rate differs from the device's output rate (for example 8, 22.05,
   32, 44.1, 48 or 96 kHz), **When** it plays, **Then** its pitch and speed are unchanged.
4. **Given** a mono track, **When** it plays, **Then** it is heard on both output channels; **given**
   a stereo track, **then** left stays left and right stays right.

---

### User Story 2 - A file that cannot be used is refused with the real reason (Priority: P1)

The user picks a file the app cannot play. The app says which kind of problem it is, in plain
words: the format is not one the app supports; the audio inside uses an encoding this device cannot
decode; the file is damaged or incomplete; the file has no audio in it; or the file could not be
opened. Nothing is added to the library, and the user can carry on immediately: import another
file, play an existing track, or keep watching what is already playing.

**Why this priority**: This is the second half of the acceptance check. Imported files are
untrusted input (Constitution, Security); a refusal has to be safe, clear and leave everything
working.

**Independent Test**: Import a text file named `.wav`, a WAV in an undecodable encoding, a file cut
off half-way, a header-only file and an empty file; each shows its own message, the library is
unchanged, and a valid file imported right afterwards plays.

**Acceptance Scenarios**:

1. **Given** a file that is not in any audio format the device can read (for example text named
   `.wav`), **When** it is picked, **Then** the app says the format isn't supported and names the
   supported formats.
2. **Given** a file in a known container whose audio encoding the device cannot decode, **When** it
   is picked, **Then** the app says the audio encoding can't be played on this device.
3. **Given** a damaged or truncated file in a known format, **When** it is picked, **Then** the
   app says the file can't be read and may be damaged.
4. **Given** a file with a valid header and no audio, or a zero-byte file, **When** it is picked,
   **Then** the app says the file contains no audio.
5. **Given** any of the refusals above, **When** it ends, **Then** the library holds exactly the
   files and tracks it held before, and importing or playing another track works at once.
6. **Given** several files picked together, some good and some bad, **When** the import ends,
   **Then** every good file is in the library and each bad one is named with its own reason.

---

### User Story 3 - The file's content decides, not its name (Priority: P2)

A user has a file with the wrong extension: a WAV saved as `song.mp3`, an AIFF named `.wav`, a raw
AAC stream named `.mp3`. The app recognizes what the file really is, imports it and plays it. A
file whose name promises audio but whose content is something else is refused as unsupported, not
as "damaged".

**Why this priority**: Misnamed files are common after downloads and conversions. Trusting the name
either refuses good files or, worse, reads a file as the wrong kind of audio.

**Independent Test**: Rename a WAV to `.mp3` and an M4A to `.wav`; both import and play. Rename a
text file to `.m4a`; it is refused as an unsupported format.

**Acceptance Scenarios**:

1. **Given** a valid file in one of the five formats under another audio extension, **When** it is
   imported, **Then** it is accepted, and it plays after an app relaunch as well.
2. **Given** a file with an audio extension whose content is not audio, **When** it is imported,
   **Then** it is refused as an unsupported format.

---

### User Story 4 - A track that goes bad later fails cleanly (Priority: P3)

A stored track's copy is damaged after import (for example by a partial device restore). When the
user taps it, the app reports "In-App Playback failed" and returns to the chooser; it does not
play silence, crash or play another track instead. Other tracks still play.

**Why this priority**: Rare, but the acceptance asks for recoverable errors, and silent playback
looks like a broken visualizer.

**Independent Test**: Import a track, overwrite its stored copy with a cut-off version, and play
it: playback fails with the message; a second, intact track then plays.

**Acceptance Scenarios**:

1. **Given** a listed track whose stored copy no longer decodes, **When** the user plays it,
   **Then** playback fails with "In-App Playback failed" and the chooser is usable.
2. **Given** that failure, **When** the user plays an intact track, **Then** it plays.

---

### Edge Cases

- A file cut off in the middle that the device can still decode up to the cut (for example a WAV
  or MP3 missing its tail): it is imported with the shorter duration the decoder reports. Only
  files the decoder cannot read through to their stated end are refused as damaged.
- An MP3 or AAC file that begins with a metadata tag (ID3): recognized by the audio after the tag.
- Lossless audio in an M4A file (Apple Lossless): the device decodes it, so it is imported and
  played like AAC. It is tested but not one of the five guaranteed fixtures.
- Other formats the device happens to decode (for example CAF or FLAC): still imported as in
  AUD-001. They are not named in messages and carry no guarantee.
- A valid audio file with a non-audio extension (`.txt`, `.bin`): still refused before copying as
  "not a supported audio file" (AUD-001-R4a); the Files picker does not offer such files.
- Random bytes that happen to begin like an audio file: refused as damaged rather than as
  unsupported. Either way nothing is imported.
- A file whose header claims an absurd length, sample rate or channel count: refused, with no
  large memory allocation and no long wait.
- More than two channels and DRM-protected files keep their AUD-001 messages.
- A very large valid file: validation reads a bounded amount regardless of file size (apart from
  the copy itself, AUD-001-R4b).

## Requirements *(mandatory)*

### Functional Requirements

**Formats**

- **AUD-002-R1**: The app MUST import and play audio in these five formats: MP3, raw AAC
  (`.aac`), M4A containing AAC, WAV and AIFF (including AIFF-C with uncompressed audio), in mono
  and stereo.
- **AUD-002-R2**: For each of the five formats the listed duration, sample rate and channel count
  MUST match the file, and playback MUST deliver non-silent audio for non-silent content.
- **AUD-002-R3**: Playback MUST preserve pitch, speed and channel placement whatever the file's
  sample rate (at least 8, 22.05, 32, 44.1, 48 and 96 kHz where the format allows) and channel
  count, including when they differ from the output's: mono is heard on both output channels;
  stereo keeps left and right.
- **AUD-002-R4**: Decoding MUST use only the device's built-in decoders. The feature MUST NOT add
  a third-party decoder, any other dependency, an entitlement or a permission prompt. Audio the
  device can decode in a supported container (for example Apple Lossless in M4A) is accepted; audio
  it cannot decode is refused (AUD-002-R7).

**Recognition by content**

- **AUD-002-R5**: What a file is MUST be decided from its content. A valid file in one of the five
  formats MUST import and play, now and after a relaunch, whatever audio extension its name
  carries, and MUST never be read as a different format because of its name.
- **AUD-002-R6**: A file with an audio extension whose content is not a recognized audio format
  MUST be refused as an unsupported format (not as damaged).

**Errors**

- **AUD-002-R7**: A refused import MUST state which of these applies, each with its own message:
  (a) unsupported format: the content is not an audio format the app can read; the message names
  the five supported formats; (b) unsupported encoding: a recognized container whose audio the
  device cannot decode; (c) damaged or incomplete: a recognized format that cannot be read through;
  (d) no audio: a zero-byte file, or a valid file with zero audio frames; (e) could not be opened:
  the picked file is unreadable. The AUD-001 reasons (not audio, DRM-protected, too large, more
  than two channels, no storage, library unavailable) are unchanged. Exact strings:
  `contracts/ui-strings.md`.
- **AUD-002-R8**: This feature amends two AUD-001 edge cases: a text file named with an audio
  extension is now refused as an unsupported format, and an empty file as containing no audio
  (both were "unreadable").
- **AUD-002-R9**: Every refusal MUST be recoverable: the library's files and record are exactly
  what they were (AUD-001-R5), no temporary file remains, and the next import, removal or playback
  works without restarting the app. A refusal MUST NOT interrupt audio that is playing.
- **AUD-002-R10**: A file cut off before its stated end MUST be refused as damaged when the device
  cannot decode its final part; a file the device decodes to a shorter end is imported with that
  duration.
- **AUD-002-R11**: Validation MUST be safe on malformed input: no crash, no hang, and memory use
  bounded independently of the file's size and of any length, rate or channel count its header
  claims.

**Playback failures**

- **AUD-002-R12**: Starting playback of a stored track whose copy is missing or no longer decodes
  MUST fail with "In-App Playback failed" (AUD-001-R19) before any audio is started; it MUST NOT
  play silence or another track. The library and the other tracks stay usable.

**Compliance**

- **AUD-002-R13**: The library's stored record keeps its format version; libraries created by
  AUD-001 stay readable and no migration is needed.
- **AUD-002-R14**: No network use, no private API, no new stored data other than the imported
  files themselves (AUD-001-R22, R23); new messages are plain text that scales with the system
  text size and is announced to VoiceOver like the existing import results (AUD-001-R24).
- **AUD-002-R15**: Test media MUST be original and generated by the project: no third-party or
  copyrighted audio in the repository.

### Key Entities

- **Audio container**: the file format recognized from content: MP3, raw AAC, M4A/MPEG-4, WAV,
  AIFF, or "other" (anything else the device may still decode).
- **Import refusal reason**: AUD-001's reasons plus unsupported format, unsupported encoding and no
  audio; "damaged" keeps its AUD-001 name and message.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **AUD-002-S1**: Five generated fixtures, one per format (MP3, AAC, M4A, WAV, AIFF), each import
  and play back non-silent audio, on the Mac and on an iOS simulator. (Roadmap acceptance, first
  half.)
- **AUD-002-S2**: Across the format matrix (five formats × mono and stereo × the sample rates each
  format allows), 100% of fixtures import with the correct duration (within 60 ms; compressed
  formats may add padding), sample rate and channel count, and play at the generated pitch within
  3%.
- **AUD-002-S3**: A corrupted fixture of every format (cut off at several points, bytes
  overwritten, header only) never crashes or hangs the app: each either imports and plays, or is
  refused with a reason, and after every refusal the library is byte-for-byte unchanged and a valid
  file imports and plays. (Roadmap acceptance, second half.)
- **AUD-002-S4**: Each refusal reason in AUD-002-R7 is produced by at least one fixture and shows
  its own message.
- **AUD-002-S5**: 100% of valid fixtures given a wrong audio extension import and play, including
  after reopening the library.
- **AUD-002-S6**: A stored copy damaged after import fails to start with "In-App Playback failed",
  and another track plays afterwards.

## Assumptions

- "Common sample rates" are 8, 11.025, 16, 22.05, 32, 44.1, 48 and 96 kHz; each format is tested at
  the rates it and the Mac's encoders support (MP3: 32, 44.1 and 48 kHz; AAC up to 48 kHz).
- The five formats are a guarantee, not a limit: other formats the device decodes keep working as
  in AUD-001.
- Apple platforms ship no MP3 encoder and none is installed on the build Mac, so the MP3 fixture is
  a valid MPEG-1 Layer III stream assembled by the project's own test code (a synthetic tone built
  from frequency-domain coefficients). It proves that a standard MP3 stream decodes; MP3 files from
  real encoders (variable bit rate, tags, joint stereo) are checked by hand in the device phase.
- Titles still come from file names; embedded tags are neither read nor shown.
- English-only strings, as in features 001 and AUD-001.
- Physical-device checks (real-world files from common encoders, output routes and interruptions
  during playback of each format) happen in the roadmap's final device phase and are tagged
  `{device}` in tasks. Simulator and Mac results are not device evidence (Constitution X).
