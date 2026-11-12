# Contract: user-visible strings added by AUD-001

English only. `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift` holds each string verbatim;
`scripts/test_scripts.py` cross-checks every table row below against it. `‹…›` marks a substituted value.
Source labels, audio states and stop reasons are unchanged (feature 001 `contracts/ui-states.md`).

## Chooser section

| Key | String |
|-----|--------|
| section title | Your Audio |
| import action | Import Audio… |
| importing | Importing… |
| empty library | No imported audio yet. |
| section footer | Imported tracks play as In-App Playback. Files are copied into the app and stay on this device. |
| remove action | Remove |
| row hint | Plays this track as In-App Playback. |

Titles the library itself generates (CaptureKit `ImportedTrack`, stored in the record, not in
`UIStrings`): "Untitled" for a file with no name, and "Recovered track ‹n›" after a damaged record
was rebuilt (AUD-001-R14).

## Import results

| Key | String |
|-----|--------|
| alert title | Import Audio |
| ok | OK |
| imported one | Imported 1 track. |
| imported many | Imported ‹n› tracks. |
| duplicate | “‹name›” is already in your library. |
| failed line | “‹name›”: ‹reason› |

## Import failure reasons (AUD-001-R6)

| AudioImportError | String |
|------------------|--------|
| notAudio | This file isn't a supported audio file. |
| unreadable | This audio file can't be read. It may be damaged. |
| protectedContent | This file is copy-protected (DRM) and can't be imported. |
| tooLarge | This file is too large. The limit is ‹limit›. |
| unsupportedChannelCount | Only mono and stereo audio can be imported. |
| insufficientStorage | There isn't enough storage on this device. |
| sourceUnavailable | This file couldn't be opened. |
| libraryUnavailable | Your audio library isn't available. |

## Library unavailable (AUD-001-R15)

| Key | String |
|-----|--------|
| newer format | Your audio library was saved by a newer version of the app. Update the app to use it. |
| storage | Your audio library couldn't be opened. |

## Accessibility

- Track row label: `‹title›, ‹spoken duration›` (for example "Song, 3 minutes 5 seconds"); hint: the
  row hint above. Visible duration: `m:ss` or `h:mm:ss`.
- Import button label: the import action text. While importing, its label is the importing text.
- After an import the result text is posted as a VoiceOver announcement.
