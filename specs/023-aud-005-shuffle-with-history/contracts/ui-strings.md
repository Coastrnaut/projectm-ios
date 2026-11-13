# Contract: shuffle strings and controls (CaptureUI)

| Key | Text |
|---|---|
| `shuffleLabel` | Shuffle |
| `shuffleValue(true)` / `(false)` | On / Off |
| `shuffleAnnouncement(on)` | "Shuffle: On" / "Shuffle: Off" |
| `shuffleIcon` | `shuffle` for both values (they differ by style, below) |
| `shuffleFooter` | "Shuffle plays the queue in a random order without changing it. Previous goes back through the tracks you played." |

Icon: On `shuffle` in the accent color with a filled background capsule; Off `shuffle` in the secondary
style. On and Off differ by more than color (the background), and VoiceOver reads the value.

Controls:

- Transport button: identifier `transportShuffle`, label "Shuffle", value "On"/"Off", shown with a
  value and an action (imported audio only), placed before Repeat; a tap toggles and announces
  `shuffleAnnouncement(newValue)`.
- Queue screen: a `Toggle` labelled "Shuffle" (identifier `shuffleToggle`) in its own section above
  Repeat, with `shuffleFooter`; a change announces the same.
