# Contract: Show keyframe tracks (SHOW-008)

- **K1 Exact.** For every keyframe k of a track, `value(at: k.time)` == k.value (numbers: same bit pattern; colours:
  each component the same bit pattern).
- **K2 Between.** For t in (t0, t1): hold → v0; linear → v0 + (v1 − v0)·u; ease → v0 + (v1 − v0)·u²(3 − 2u);
  colours per channel in linear light, alpha linear. Before the first key → first value; after the last → last value.
- **K3 Pure.** `value(at:)` depends only on the track and t.
- **K4 File.** `tracks` written only when non-empty, sorted keys; decode → encode is byte-identical; a bad track
  (ID, parameter, duplicate, over 16) or keyframe (time, value, kind mismatch, duplicate time, interpolation, over 256)
  is dropped with a counted warning; the show still loads.
- **K5 Live.** The app applies a track output only when it changed; a seek to a keyframe time applies that value once;
  at Standby or off the timeline the output is empty (manual values). MIDI/OSC values win over track numbers.
- **K6 Edit.** Add Keyframe at Playhead replaces a keyframe at the same time; numbers are clamped to the target's range
  when stored; every edit is refused while the scene is locked.
- **K7 UI.** `showKeyframeTracks` list; `showKeyframeAddTrack` menu; per track `showKeyframeAddKey`; keyframe rows
  `showKeyframeRow` with label "0:30, 1.50, Linear"; `showKeyframePlayhead` text.
