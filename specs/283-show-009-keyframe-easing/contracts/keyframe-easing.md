# Contract: SHOW-009 Keyframe Easing

- **E1 Exact keys**: for every mode, `value(at: key.time) == key.value` bit for bit.
- **E2 Two-key references** (keys (0 ms, 0.0), (1000 ms, 1.0)), at 500 ms: Linear 0.5, Stepped 0.0, Hold 0.0,
  Ease 0.5, Cubic 0.5; Cubic at 250 / 750 ms: 0.15625 / 0.84375 (|error| ≤ 1e-9).
- **E3 Hold vs Stepped**: keys (0, 0.0, Linear), (1000, 1.0, M), (2000, 0.0): at 500 ms M = Stepped → 0.5,
  M = Hold → 0.0; at 1500 ms both → 1.0.
- **E4 Cubic reference**: keys (0, 0), (1000, 1), (3000, 2), all Cubic: at 500 ms the value equals the Hermite
  formula with m0 = 0, m1 = 9000 / 13 000 000 per ms (research D2) within 1e-9; the slope at 1000 ms is not zero.
- **E5 No overshoot**: a multi-key Cubic track sampled every 10 ms stays inside each segment's key range.
- **E6 Storage**: every mode round-trips; Hold and Cubic write `easing`; other modes write no `easing`; a keyframe
  without `interpolation` loads as Linear; `"hold"` without `easing` loads as Stepped; an unknown `easing` falls back to
  `interpolation`.
- **E7 Live path**: a playing show (manual clock) applies the Cubic value at a segment's middle and holds before a
  Hold key.
- **E8 Editor**: the picker offers Linear, Stepped, Hold, Ease, Cubic; choosing Cubic makes the row read "…, Cubic";
  disabled while the scene is locked; Add Keyframe at Playhead keeps the mode of a replaced keyframe.
