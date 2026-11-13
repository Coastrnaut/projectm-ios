# Contract: route strings (AUD-007)

Exact texts, defined once in CaptureUI's `UIStrings`. `<names>` is the shown ports' names joined by
", "; `<name>` one port's name. A name is iOS's port name verbatim, or, when empty, the generic name.

## Generic names

| Kind | Generic name |
|---|---|
| builtInSpeaker | Speaker |
| builtInReceiver | Receiver |
| wiredHeadphones | Headphones |
| bluetoothA2DP, bluetoothLE, bluetoothHFP | Bluetooth device |
| airPlay | AirPlay device |
| hdmi | HDMI |
| usbAudio | USB audio device |
| carAudio | Car audio |
| lineOut | Line out |
| builtInMic | Built-in mic |
| headsetMic | Headset mic |
| lineIn | Line in |
| other, otherInput | Audio device |

## Indicator (identifier `routeIndicator`)

| Context | Text | VoiceOver label |
|---|---|---|
| playback | `Output: <names>` | `Audio output: <names>` |
| microphone | `Input: <names>` | `Audio input: <names>` |
| no ports | `Output: None` / `Input: None` | `Audio output: None` / `Audio input: None` |

Icon (SF Symbol) by the first port's kind: speaker `speaker.wave.2`, receiver `iphone`, wired
headphones `headphones`, Bluetooth `wave.3.right`, AirPlay `airplayaudio`, HDMI/USB/line/other
`hifispeaker`, car audio `car`, inputs `mic`, none `speaker.slash` / `mic.slash`. The icon is hidden
from VoiceOver.

## Explanation (identifier `routeExplanation`, about 4 s)

| Summary | Context | Text | Announced |
|---|---|---|---|
| switched(to: P) | playback, not held by user | `Now playing through <P>` | yes |
| switched(to: P) | playback, held by user | `Audio output is now <P>` | yes |
| switched(to: P) | microphone | `Now listening through <P>` | yes |
| lost(L), reason pauses | playback, not held by user | `<L> disconnected — paused` | no (AUD-014-R18 announces) |
| lost(L) | any other | `<L> disconnected` | yes |
| noneLeft | playback | `No audio output available` | yes |
| noneLeft | microphone | `No audio input available` | yes |
| nil | any | none | no |

## Wording rules (AUD-007-R11)

- The app's own wording (every template above with the name removed, and every generic name) contains
  none of the source-mode labels "System/App Capture", "Microphone", "In-App Playback", and not
  "capture" in any case, and names no app.
- Output wording never says audio comes from the route ("from", "receiving", "listening" are not used
  for outputs).
- The existing source-and-state texts (FR-042), AUD-014's texts and every Microphone and
  System/App Capture text are unchanged.
