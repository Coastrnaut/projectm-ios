# Data model: AUD-016 Reference tone suite

All types are value types, `Sendable`, `Hashable`, in memory only. Nothing is persisted.

## AudioCore (`Packages/AudioCore/Sources/AudioCore/ReferenceTones/`)

### `ToneFormat`

| Field | Type | Rule |
|---|---|---|
| `sampleRate` | `Int` | 8,000…192,000 |
| `channels` | `Int` | 1 or 2 |

`init(sampleRate:channels:) throws(ToneError)`; constants `canonical` (48,000 Hz, 2 channels).

### `ToneSignal` (enum)

| Case | Payload | Rules |
|---|---|---|
| `.sine(SineTone)` | `left: Double?`, `right: Double?` (Hz; nil = that channel silent), `amplitude: Double` | each frequency 1 Hz ≤ f < rate/2; at least one frequency; mono needs `left == right` |
| `.sweep(SweepTone)` | `start`, `end` (Hz), `seconds`, `amplitude`, `curve: .logarithmic / .linear` | frequencies 1 Hz ≤ f < rate/2; seconds 0.01…600; the sweep repeats every `seconds` |
| `.pulses(PulseTrain)` | `beatsPerMinute`, `widthSeconds`, `amplitude`, `accents: [Double]` | BPM 1…600; width ≥ 1 frame and < the shortest beat period; 1…32 accents, each 0…1 |
| `.silence` | — | — |

Amplitude: finite, 0…1. Every validation failure is a `ToneError` naming the parameter:
`sampleRate(Int)`, `channelCount(Int)`, `frequency(Double)`, `amplitude(Double)`, `duration(Double)`,
`tempo(Double)`, `pulseWidth(Double)`, `accents`, `monoNeedsEqualChannels`, `noFrequency`.

### `ToneGenerator`

Validated pair of a `ToneSignal` and a `ToneFormat`. Pure: `sample(frame:channel:) -> Float` is a
function of the frame index alone; `render(into:frames:startFrame:)` (interleaved) and
`render(left:right:frames:startFrame:)` (planar) write into caller storage and do not allocate;
`interleaved(frames:startFrame:) -> [Float]` allocates (tests, catalog).

### `ReferenceToneFixture`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | stable, e.g. `sine-1k`; never reused for other samples |
| `name` | `String` | display name, begins with "Test" |
| `summary` | `String` | one line for the list |
| `signal` | `ToneSignal` | |
| `loopSeconds` | `Int` | 10 for every v1 fixture |
| `layouts` | `[Int]` | channel counts with golden hashes: `[1, 2]`, or `[2]` for `sine-split` |

Expected values (pure, from the parameters; AUD-016-R11): `nearestBin(frequency:fftSize:sampleRate:)`,
`exactBin(…)`, `isBinCentered(…)`, `onsetFrames(sampleRate:)` (one loop), `onsetAccents`,
`interOnsetFrames(sampleRate:)`, `beatsPerMinute`, `instantaneousFrequency(atSeconds:)`.

### `ReferenceToneCatalog`

`version: Int` (1), `fixtures: [ReferenceToneFixture]` in display order, `fixture(id:)`,
`variantRates` (44,100 and 48,000), `playbackFormat` (= `ToneFormat.canonical`).
Rule: a change to any fixture's samples raises `version` and its golden hashes are replaced.

## CaptureKit

- `InAppPlaybackTrack.tone(ReferenceToneFixture)`: a new case. Never persisted (as `.file`).
- `PlaybackItem.tone(_:)`: `id = "tone.<fixture id>"`, `title = fixture.name`,
  `durationSeconds = loopSeconds`, `track = .tone(fixture)`.
- `InAppPlaybackGraph.Content`: storage is either two file handles (unchanged) or one
  `AVAudioPCMBuffer` (48 kHz, stereo, planar float, `loopSeconds × 48,000` frames).

State transitions are those of the AUD-006 transport and AUD-014 policy; a tone item is always an
order of one (`ListPlayOrder([item])`), so it loops and never ends.

## App

- `AppCoordinator.playTestSignal(_ fixture:)` prepares the transport with the tone item and starts
  In-App Playback. No property is stored in `UserDefaults` or on disk.
- `SourceStatusIndicator.text(mode:state:signal:)`: `signal` is the current item's title when its
  track is `.tone`.
