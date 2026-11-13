# UI strings: AUD-016 Reference tone suite

English only, verbatim in `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`; tests in
`Packages/CaptureUI/Tests/CaptureUITests/TestSignalStringsTests.swift` check them.

| Key | Text |
|---|---|
| `diagnostics` (section header) | Diagnostics |
| `testSignals` (row and list title) | Test Signals |
| `testSignalsRowDetail` | Generated tones, sweeps, pulses and silence for checking the visualizer. |
| `testSignalsFooter` (list footer) | These test signals are generated on this device for checking the visualizer. They are not music. Lower the volume before you start one. Each plays as In-App Playback and repeats until you stop it. |
| `testSignalHint` (row hint) | Plays this test signal as In-App Playback. |
| status line | `In-App Playback · <signal name> · <state>` (`sourceStatus(mode:state:signal:)`) |

Signal names and summaries come from the catalog (`contracts/fixture-catalog.md`). The transport
title is the signal name. No other string changes.
