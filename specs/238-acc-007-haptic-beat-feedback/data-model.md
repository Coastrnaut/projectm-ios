# Data Model: ACC-007 Haptic Beat Feedback

| Entity | Fields | Rules |
|---|---|---|
| `HapticBeatChoice` (String) | `beats`, `downbeats`, `kicks` | Stored `settings.haptics.beatEvent`; absent or unknown → `beats`. |
| `HapticPulseStrength` (String) | `light`, `medium`, `strong` | Stored `settings.haptics.strength`; absent or unknown → `medium`. |
| enabled (Bool) | — | Stored `settings.haptics.beatPulses`; absent → false. Written on change only. |
| `HapticCue` | `.beat(confidence)`, `.kick`, `.sessionBoundary` | From `AnalysisEvent`; other kinds map to nil. |
| `HapticPulseRules` | minimum interval 150 ms, 4 per 1 s, 180 per 60 s, stale 200 ms, 4 beats per bar, beat confidence ≥ 0.5 | `.standard`; tests may pass others. |
| `HapticPulseDecision` | `pulse`, `filtered`, `suppressed`, `stale`, `throttled` | One per considered cue. |
| `HapticPulseGate` | rules, choice, beat count, ring of the last 180 pulse times, counters | Value type; no allocation after init. |
| `HapticPlaying` | `play(strength:intensity:)` | Main actor; the fake records calls. |

Storage: all three keys local (UserDefaults), in FILE-005 `includedKeys`, `ALLOWED_KEYS`, cleared by
`-uitestResetNotice`; never in scenes, cues, MIDI, OSC or modulation.
