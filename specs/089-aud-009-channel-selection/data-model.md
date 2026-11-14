# Data Model: AUD-009 Channel Selection

## AnalysisChannelMode (AudioCore, `enum: UInt8, CaseIterable, Sendable`)

| Case | Raw (UInt8) | Stored string | Short title | Spoken name | s per frame |
|---|---|---|---|---|---|
| `mix` (default) | 0 | `mix` | Mix | Stereo mix | (L + R)·0.5 |
| `left` | 1 | `left` | Left | Left | L |
| `right` | 2 | `right` | Right | Right | R |
| `mid` | 3 | `mid` | Mid | Mid | (L + R)·(1/√2) |
| `side` | 4 | `side` | Side | Side | (L − R)·(1/√2) |

Validation: unknown UInt8 → `mix`; unknown or missing stored string → `mix`.

## ChannelSelectionControl (AudioCore, `final class: Sendable`)

- `mode: AnalysisChannelMode` — get/set, lock-free (`Atomic<UInt8>`, relaxed).

## ChannelSelectionReader (AudioCore, `NormalizedPCMReader`, `AnalysisSessionReporting`)

- Wraps one reader and one control; no other state. One consumer thread.

## ChannelSelectionSetting (app, `@MainActor @Observable`)

- `mode: AnalysisChannelMode` — persisted under `settings.analysisChannel.mode` on every set.
- `control: ChannelSelectionControl` — mirrors `mode`.
- `selected(_ tap:) -> (any NormalizedPCMReader)?` — a new `ChannelSelectionReader` per consumer.
