# Data Model: MED-012 Countdown Overlay

## CountdownTimer (value, TextLayer)
| Field | Type | Rule |
|---|---|---|
| durationSeconds | Int | 1…5,940 (clamped) |
| accumulated | Double | running seconds before the current segment, ≥ 0 |
| startedAt | Double? | monotonic seconds of the current segment's start; nil when not running |
| hasFinished | Bool | set once when remaining reaches 0; cleared by Reset/Start |

States: idle (accumulated 0, not running) → running → paused ↔ running → finished. Reset → idle.
Start on finished → idle → running. `remaining(at:) = max(0, duration − elapsed)`.

## CountdownOverlaySettings (stored, `settings.countdown.overlay`, JSON `"version": 1`)
| Field | Type | Default |
|---|---|---|
| isShown | Bool | false |
| durationSeconds | Int | 300 (1…5,940) |
| startsFromCues | Bool | false |
| style | TextOverlaySpec (message empty) | top, centre, 8 %, Menlo bold, white, outline |

Missing → defaults; damaged → defaults and removed; newer version → defaults, untouched.

## Scene field `countdown` (SCN-001 document, optional)
`{"durationSeconds": <integer 1…5940>}`, exactly that key. Anything else reads as absent and is kept
verbatim.
