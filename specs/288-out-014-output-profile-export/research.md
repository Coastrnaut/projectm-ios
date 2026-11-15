# Research: OUT-014 Output Profile Export

## OUT-014-D1: Where the codec lives
- Decision: PresentationLifecycle (pure Swift, Linux-tested, already in CI), next to `CornerPin` and the output enums.
- Rationale: the corner pin validator and every enum are there; tests run on the host and Linux.
- Alternatives: Compositor (owns `DisplayCalibration`, but PresentationLifecycle must not depend on it: heavy graph);
  the app target (no Linux tests).
- Consequence: calibration ranges are duplicated as `OutputProfile.Calibration.gammaRange/trimRange`; an app test
  asserts they equal `DisplayCalibration.gammaRange/trimRange`, so the settings' rule and the import rule cannot drift.

## OUT-014-D2: Strictness
- Decision: reject (never clamp) out-of-range values, unknown or missing fields, unknown names, non-integer percentage.
- Rationale: clamping would silently change a calibration (the acceptance is exact reproduction); MIDI-012 and SHD-011
  refuse untrusted input the same way. Unknown fields are refused so a file can never carry data the app ignores.

## OUT-014-D3: Display class
- Decision: native pixel width/height, the screen's own pixel aspect (`UIScreenMode.pixelAspectRatio`, sanitised as
  OUT-004 does, not the user's override), refresh rate, gamut. Match: same size, pixel aspect within 0.005, same gamut
  when both report it; refresh not compared. Unknown when either side has no class.
- Rationale: the corner pin and resolution are relative to the display's pixel geometry, the calibration to its colour
  space; refresh does not change either.

## OUT-014-D4: Export path
- Decision: SwiftUI `fileMover` of a temporary file (MIDI-012), `fileImporter` for `.data`, at most 16 KB + 1 read.
- Rationale: proven in this app, local only, no share sheet network targets.

## OUT-014-D5: Exactness
- Decision: the document stores the in-memory `Double`s; `JSONEncoder` writes the shortest round-trip form, so decoding
  yields the same bits. Applying sets the setting's properties (the stored keys keep their own precision, as when the
  user drags a slider).
