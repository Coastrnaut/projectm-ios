# Contract: user-visible strings added by AUD-002

English only. `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift` holds each string verbatim;
`scripts/test_scripts.py` cross-checks every table row below against it. All other strings are
those of `specs/003-aud-001-import-drm-free-audio-files/contracts/ui-strings.md`, unchanged.

## Import failure reasons (AUD-002-R7)

| AudioImportError | String |
|------------------|--------|
| unsupportedFormat | This file's format isn't supported. Import MP3, AAC, M4A, WAV or AIFF audio. |
| unsupportedEncoding | The audio in this file uses an encoding this device can't play. |
| noAudio | This file contains no audio. |

Unchanged and still used by this feature: `unreadable` ("This audio file can't be read. It may be
damaged.") for damaged or truncated files, and `sourceUnavailable` ("This file couldn't be
opened.") for a picked file that cannot be read.

A failed line in the import summary keeps its form: `“‹name›”: ‹reason›`. Playback failures keep
feature 001's "In-App Playback failed".
