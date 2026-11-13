# Contract: repeat UI and strings (AUD-004, CaptureUI)

| Key | Text |
|---|---|
| `UIStrings.repeatLabel` | Repeat |
| `UIStrings.repeatValue(.off)` | Off |
| `UIStrings.repeatValue(.one)` | One Track |
| `UIStrings.repeatValue(.all)` | All Tracks |
| `UIStrings.repeatAnnouncement(mode)` | Repeat: ‹value› |
| `UIStrings.repeatFooter` | Off stops after the last track. One Track repeats the current track. All Tracks starts the queue again after the last track. |
| `UIStrings.repeatIcon(mode)` | `repeat` (off, all), `repeat.1` (one) |
| `UIStrings.repeatChoices` | Off, One Track, All Tracks (the queue screen's row order) |

## TransportBar

`TransportBar(…, repeatMode: RepeatMode? = nil, onCycleRepeat: (() -> Void)? = nil)`. A button is
shown only when both are given, after Next track and before Queue: identifier `transportRepeat`,
label "Repeat", value `repeatValue(mode)`, icon `repeatIcon(mode)`, secondary style for Off, accent
for One and All. A tap calls `onCycleRepeat` and announces `repeatAnnouncement` of the next mode.

## PlayQueueView

A section "Repeat" (after "Play Queue", before "Up Next") (header `repeatLabel`, footer `repeatFooter`) with three rows in the order
Off, One Track, All Tracks; identifier `repeatMode.<raw value>`; the current one has a checkmark and
the `.isSelected` trait; a tap calls `queue.setRepeatMode` and announces. Rows grow with Dynamic Type.
