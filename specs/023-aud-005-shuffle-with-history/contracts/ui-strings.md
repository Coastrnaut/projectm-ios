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
- Queue screen: a `Toggle` labelled "Shuffle" (identifier `shuffleToggle`) in its own section right
  after "Up Next", with `shuffleFooter`; a change announces the same. (First placed above Repeat; that
  pushed the queue rows down so far that `PlayQueueUITests`' long-press on the third row met the
  bottom toolbar, 2026-11-13; after the list, every existing row keeps its place.)
