# Contract: user-visible strings added by AUD-006

English only. `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift` holds each string verbatim;
`scripts/test_scripts.py` cross-checks every table row below against it. All other strings are
those of feature 001's `contracts/ui-states.md` and of AUD-001 and AUD-002, unchanged.

## Transport controls (AUD-006-R24, R26)

Each string is the control's accessibility label; the buttons show icons.

| Control | String |
|---------|--------|
| play | Play |
| pause | Pause playback |
| stop | Stop playback |
| previousTrack | Previous track |
| nextTrack | Next track |
| scrubber | Playback position |
| referenceTrackTitle | Reference track |

The existing controls keep their labels: "Stop" (stop the source and return to the chooser),
"Pause"/"Resume" (freeze the picture), "Previous"/"Next" (presets).

## Times

- Elapsed time: `m:ss`, or `h:mm:ss` from one hour (the AUD-001 duration format).
- Remaining time: the same format with a leading minus sign (U+2212), for example `−1:05`.
- Scrubber value for VoiceOver: `‹elapsed› of ‹length›` with spoken durations, for example
  "1 minute 5 seconds of 3 minutes".

| Pattern | String |
|---------|--------|
| scrubberValue | ‹elapsed› of ‹length› |

## Status

While playback is paused or stopped by the user the source indicator reads
"In-App Playback · Paused" (feature 001 strings; no new status string).
