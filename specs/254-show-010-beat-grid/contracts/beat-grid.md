# Contract: SHOW-010 Beat Grid

## G1 Ticks (ShowControl)
`BeatGrid.ticks(tempo, from: start, to: end, stride: s = 1) -> [BeatGridTick]`: nil tempo or end < start → `[]`.
Otherwise every k with `start ≤ anchor + k·period ≤ end` and `k % s == 0`, ascending; `isBar = k % 4 == 0`; the
stride doubles (1 → 4 → 8 …) until the count ≤ `BeatGrid.maximumTicks` (512).

## G2 Stride
`BeatGrid.stride(tempo, duration:, width:) -> Int64`: the smallest of 1, 4, 8, 16 … with
`period·s / duration × width ≥ 4` points and at most 512 ticks over [0, duration].

## G3 Marks
`BeatGrid.marks(tempo, duration:, width:, inset:)`: the ticks over [0, duration] at the chosen stride, each at
`x = inset + t / duration × (width − 2·inset)`. Empty without a tempo or for a zero duration.

## G4 Position and texts
`position(tempo, at:)`: k = ⌊(t − anchor) / period⌋, bar = ⌊k/4⌋ − ⌊⌊(0 − anchor)/period⌋/4⌋ + 1, beat = k − 4⌊k/4⌋ + 1.
`readoutText`: "Bar B · Beat b · N BPM", "N BPM" without a time, "No tempo". `accessibilityValue`: "N BPM, tap tempo|detected,
bar B beat b", "N BPM, tap tempo|detected", "No tempo". N is the BPM rounded to a whole number.
`nearestBeat(tempo, to:)`: the closest beat (ties go later).

## G5 App placement
`ShowBeatGridCoordinator.tempo()` → `BeatGridTempo?` from `TempoSnapshot` (nil for `.none`). Anchor on the timeline:
playing with an anchor → `(timelineNow − (tempoNow − anchor)) mod period` (stored); otherwise the stored placement,
else 0.

## G6 Row
`ShowScrubBar` draws the marks under the thumb (beats 8 pt, bars 16 pt high; hidden from VoiceOver); the gesture is
unchanged. `showBeatGridReadout` (label "Beat grid", value per G4 at the displayed time). DEBUG `-uitestBeatGridProbe`:
text `showBeatGridProbe` = "ticks N stride S".
