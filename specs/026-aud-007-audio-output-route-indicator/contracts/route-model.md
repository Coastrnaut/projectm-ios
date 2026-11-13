# Contract: route model (AUD-007)

## Port-type mapping (`RoutePortKind(portType:)`)

| Port type raw value (SDK constant) | Kind |
|---|---|
| `Speaker` (`builtInSpeaker`) | builtInSpeaker |
| `Receiver` (`builtInReceiver`) | builtInReceiver |
| `Headphones` (`headphones`) | wiredHeadphones |
| `BluetoothA2DPOutput` (`bluetoothA2DP`) | bluetoothA2DP |
| `BluetoothLE` (`bluetoothLE`) | bluetoothLE |
| `BluetoothHFP` (`bluetoothHFP`) | bluetoothHFP |
| `AirPlay` (`airPlay`) | airPlay |
| `HDMIOutput` (`HDMI`) | hdmi |
| `USBAudio` (`usbAudio`) | usbAudio |
| `CarAudio` (`carAudio`) | carAudio |
| `LineOut` (`lineOut`) | lineOut |
| `MicrophoneBuiltIn` (`builtInMic`) | builtInMic |
| `MicrophoneWired` (`headsetMic`) | headsetMic |
| `LineIn` (`lineIn`) | lineIn |
| anything else, as an output | other |
| anything else, as an input | otherInput |

The simulator test checks every SDK constant in the left column maps to the kind on the right.

## Change summary (`AudioRouteChange.summary(direction)`), first match wins

1. `reason == .categoryChange` → nil.
2. `reason == .oldDeviceUnavailable` and a previous port is missing now → `.lost(first missing port)`.
3. No ports now, but some before → `.noneLeft`.
4. The first port changed, or a port was added → `.switched(to: first added port, else the new first port)`.
5. Otherwise → nil.

Ports are compared by kind and name.

## Shared pause rule

`AudioRouteChangeReason.pausesInAppPlayback` is true only for `oldDeviceUnavailable`.
`AudioSessionSignal.parse` returns `.outputRouteLost` for a route change exactly when it is true
(AUD-014-R14 unchanged). An explanation says "— paused" exactly when the summary is `.lost`, the
context is `.playback(heldByUser: false)` and `pausesInAppPlayback` is true.

## Context

| Active mode | State | Context |
|---|---|---|
| In-App Playback | waiting, noAudioReceived, silent, active, paused, interrupted | `.playback(heldByUser: isPausedByUser)` |
| Microphone | same states | `.microphone` |
| System/App Capture, none | any | nil (no indicator, no explanation) |
| any | notStarted, stopped, endedBySystem | nil |
