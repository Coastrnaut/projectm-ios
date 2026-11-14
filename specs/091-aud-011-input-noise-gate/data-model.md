# Data Model: AUD-011 Input Noise Gate

## NoiseGateParameters (AudioCore, value)

| Field | Type | Default | Bounds | Notes |
|---|---|---|---|---|
| openDecibels | Float | −50 | −80…−20 | NaN → default |
| hysteresisDecibels | Float | 6 | 0…20 | close = open − hysteresis |
| attackSeconds | Float | 0.005 | 0.0005…0.05 | → `attackFrames` = max(1, round(s·44,100)) = 221 |
| holdSeconds | Float | 0.100 | 0…1 | → 4,410 frames (0 allowed) |
| releaseSeconds | Float | 0.150 | 0.010…2 | → 6,615 frames |

Detector release: fixed 10 ms (r = exp(−1/441)).

## NoiseGateControl (AudioCore, shared, lock-free)

- `isEnabled: Bool`, `isMicrophoneSource: Bool` (one `Atomic<UInt8>` of flag bits);
  `openDecibels: Float` (`Atomic<UInt32>` bit pattern, clamped on store); `isActive` = both flags.

## NoiseGateProcessor (AudioCore, per reader)

- `envelope: Float`, `gain: Float` (0…1), `phase: Phase` (closed, attack, open, release),
  `holdRemaining: Int`, cached linear open/close thresholds and the dB they came from.
- Transitions: closed —e ≥ open→ attack —gain = 1→ open; open: e ≥ close ⇒ hold = holdFrames,
  else hold −= 1, at 0 → release; release —gain = 0→ closed; release —e ≥ open→ attack.
- `reset()`: closed, gain 0, e 0.

## NoiseGateReader (AudioCore)

- Wraps a `NormalizedPCMReader`; holds the control, a processor, `wasActive`, last generation.

## NoiseGateSetting (app, @Observable, main actor)

| Key | Type | Default | Validation |
|---|---|---|---|
| `settings.noiseGate.enabled` | Bool | false | non-Bool → false |
| `settings.noiseGate.thresholdDecibels` | Double | −50 | NaN/non-number → −50; clamped −80…−20; whole dB |

- Mirrors both into a `NoiseGateControl`; `gated(_:)` wraps a reader; `text(for:)` → "−50 dBFS".
