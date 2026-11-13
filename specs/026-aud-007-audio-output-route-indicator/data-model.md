# Data model: AUD-007 Audio output route indicator

All types are values in CaptureKit, `Sendable` and `Equatable`, held in memory only (AUD-007-R14).

## RoutePortKind

Output kinds: `builtInSpeaker`, `builtInReceiver`, `wiredHeadphones`, `bluetoothA2DP`,
`bluetoothLE`, `bluetoothHFP`, `airPlay`, `hdmi`, `usbAudio`, `carAudio`, `lineOut`, `other`.
Input kinds: `builtInMic`, `headsetMic`, `lineIn`, `otherInput` (Bluetooth HFP, USB and car audio
are shared with outputs). Built from the port-type raw string (contracts/route-model.md).

## RoutePort

| Field | Type | Rule |
|---|---|---|
| `kind` | RoutePortKind | from the port type |
| `name` | String | iOS's port name, verbatim (may be empty) |

Identity for change detection: `kind` and `name` together.

## AudioRoute

| Field | Type |
|---|---|
| `inputs` | [RoutePort], iOS's order |
| `outputs` | [RoutePort], iOS's order |

`ports(_ direction: RouteDirection) -> [RoutePort]`; `.empty` is no ports.

## AudioRouteChangeReason

`unknown` 0, `newDeviceAvailable` 1, `oldDeviceUnavailable` 2, `categoryChange` 3, `override` 4,
`wakeFromSleep` 6, `noSuitableRouteForCategory` 7, `routeConfigurationChange` 8 (raw values of the
SDK). Unknown raw values → `unknown`. `pausesInAppPlayback`: true only for `oldDeviceUnavailable`.

## AudioRouteChange

| Field | Type |
|---|---|
| `sequence` | Int, starts at 1 and increases per change |
| `reason` | AudioRouteChangeReason |
| `previous` | AudioRoute |
| `current` | AudioRoute |

`summary(_ direction:) -> RouteChangeSummary?`:
`.lost(RoutePort)`, `.noneLeft`, `.switched(to: RoutePort)`; nil when nothing to explain.

## AudioRouteContext

`.playback(heldByUser: Bool)` → direction outputs; `.microphone` → direction inputs.
`AudioRouteContext.make(mode:state:isPausedByUser:)`: In-App Playback in any state but
`notStarted`, `stopped`, `endedBySystem` → playback; Microphone likewise → microphone; otherwise nil
(no indicator).

## AudioRouteMonitor (state)

| Property | Meaning |
|---|---|
| `route` | the last route read from the provider |
| `lastChange` | the newest AudioRouteChange, nil before the first |

Transitions: `refresh()` reads the provider and replaces `route` without a change;
`routeDidChange(reason:)` reads the provider, records a change from the old route, calls `onChange`.
