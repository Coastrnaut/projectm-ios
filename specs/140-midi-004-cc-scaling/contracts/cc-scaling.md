# Contract: MIDI-004 MIDI CC Scaling

## C1 Values (pure, PerformanceControl)

- C1.1 `MIDIBindingValues.value(normalized:for:options:)`: for every curve kind and every continuous range,
  normalized 0 → exactly the minimum and 1 → exactly the maximum; inverted, 0 → maximum and 1 → minimum.
- C1.2 Inverted at v equals non-inverted at 127 − v (to within 1e-12 of the span).
- C1.3 The result is always within [minimum, maximum]; non-finite input reads 0.
- C1.4 `values(for:bindings:registry:)` applies each binding's own options.

## C2 Stored form (pure)

- C2.1 A default binding's line equals MIDI-003's line.
- C2.2 `cc:0:7=a;curve=log:9.0;invert=1;min=0.2` reads curve log 9, inverted, extra `["min=0.2"]`, and
  writes back the same line.
- C2.3 Unreadable or invalid curve text reads Linear, is flagged and written back unchanged.
- C2.4 Empty segments are dropped; repeated known keys keep the first.

## C3 List (pure)

- C3.1 Relearning a parameter with another control keeps its options; moving a control onto another
  parameter gives it that parameter's options (default when it had none).
- C3.2 `setOptions` changes only that binding; unmapped → false.

## C4 App

- C4.1 `MIDIMappingCoordinator.selectPreset(_:for:)` and `setInverted(_:for:)` save at once, announce on
  `.midi` ("Glow intensity curve: Ease in." / "Glow intensity inverted." / "Glow intensity not inverted."),
  and create no Undo entry.
- C4.2 Rows: mapped rows carry `curveSummary`; the "Curve" row has identifier `midiCurve.<parameter ID>`.
- C4.3 Options screen: picker `midiCurvePicker`, toggle `midiInvert`, preview `midiCurvePreview`, notice
  `midiCurveNotice` when flagged.
- C4.4 Values from a fake MIDI source honour options end to end.
