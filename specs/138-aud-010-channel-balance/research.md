# Research: AUD-010 Channel Balance

## AUD-010-D1: How to realise the balance law

- **Decision**: A dedicated `AVAudioMixerNode` after the main mixer; set
  `mainMixerNode.destination(forMixer: balanceNode, bus: 0)?.pan = b`.
- **Rationale**: Measured on 2026-11-14 (macOS 27.2 host, offline manual rendering, a stereo buffer
  with a 440 Hz tone at 0.5 on the left and 1 kHz at 0.25 on the right): output RMS left/right at
  pan −1: 0.3536 / 0.0; −0.5: 0.3536 / 0.0884; 0: 0.3536 / 0.1768; 0.5: 0.1768 / 0.1768; 1: 0.0 /
  0.1768. That is exactly a linear balance: near side unity, far side × (1 − |p|), no fold-over (the
  left RMS at −1 equals the left tone alone; with the right folded in it would be 0.395). So the
  brief's concern that the mixer pan is mono-panning for stereo does not hold for a stereo input bus;
  it does hold for a mono source panned into stereo, which is why the balance is applied to the
  already-stereo main-mixer output and never to the player. Tests pin this law at five points on the
  host and on the simulator, so an OS change fails a test.
- **Alternatives considered**: (a) `AVAudioUnit` matrix mixer with per-crosspoint gains: exact
  control, but fiddly (every volume defaults to 0) and more graph code beside REC-004's edits.
  (b) Our own DSP via `AVAudioSourceNode` fed from a ring after the tap: adds latency, render-thread
  Swift and a second buffer path; rejected (Constitution VII). (c) `player.pan`: before the tap, so
  it would change the analysis; rejected (R3).

## AUD-010-D2: Where the tap sits

- **Decision**: unchanged: main mixer output bus 0. The balance node is downstream of it, so the tap
  cannot see the balance. Proven by the acceptance test (analysis PCM identical at −1, 0, +1) and by
  a test that changes the balance mid-play with no discard.
- **Format**: the two new connections use the main mixer's output format as it is right after the
  player is connected (the format the implicit main-mixer→output connection had), so the tap's format
  and the rendered output are as before.

## AUD-010-D3: Value, detent and text

- −1…+1, rounded to whole percent; |b| ≤ 0.03 → 0. Readout "Centered", "30% left", "30% right";
  VoiceOver "centered", "30 percent left". VoiceOver step 0.1.

## AUD-010-D4: Availability

- `PlaybackBalanceSetting.isAvailable(for: activeMode)` = `activeMode == .inAppPlayback`. Settings
  receives the active mode from the coordinator (`manager.activeMode`, observable).
