# Data Model: AUD-002 Support common audio containers

Nothing persistent changes: `index.json` stays at `schemaVersion` 1 with AUD-001's fields
(`specs/003-aud-001-import-drm-free-audio-files/data-model.md`).

## AudioContainer (new, in memory only)

| Case | Recognized by (leading bytes) | Canonical extension |
|---|---|---|
| `mp3` | MPEG audio header, Layer III (after an optional ID3v2 tag) | `mp3` |
| `aac` | ADTS header (after an optional ID3v2 tag) | `aac` |
| `mpeg4` | `ftyp` box at offset 4 | `m4a` |
| `wav` | `RIFF` … `WAVE` | `wav` |
| `aiff` | `FORM` … `AIFF` or `AIFC` | `aiff` |

`nil` means "not one of these"; the picked extension is then kept.

## ImportedTrack.fileName (rule extended)

`<sha256>.<ext>`: `<ext>` is the recognized container's canonical extension, else the picked
file's extension reduced as in AUD-001 (lowercase ASCII letters and digits, at most 8), else
absent. `originalFileName` and `title` still come from the picked name.

## AudioFileInfo (extended, in memory only)

`durationSeconds`, `sampleRate`, `channelCount` (AUD-001) plus `container: AudioContainer?`.

## AudioImportError (extended)

AUD-001: `notAudio`, `unreadable`, `protectedContent`, `tooLarge(limitBytes)`,
`unsupportedChannelCount(count)`, `insufficientStorage`, `sourceUnavailable`, `libraryUnavailable`.

New:

| Case | Meaning |
|---|---|
| `unsupportedFormat` | audio extension, but the content is no audio format the app or the device recognizes |
| `unsupportedEncoding` | recognized container; the device has no decoder for the audio inside |
| `noAudio` | zero-byte file, or a valid file with zero audio frames |

`unreadable` now means only: a recognized format that is damaged or incomplete.

## Import state machine (one file; changes in bold)

```text
picked → typeChecked → copying(incoming) → **[0 bytes] → failed(noAudio)**
       → hashed → [hash in library] → duplicate
       → **recognized → staged file renamed to the canonical extension**
       → inspected (**start and end decode**) → moved(assets, **canonical name**) → indexed → imported
any failure → staged file deleted under its current name → failed(reason)
```
