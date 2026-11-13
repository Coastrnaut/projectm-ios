# Research: AUD-007 Audio output route indicator

All decisions below use public APIs from the iOS 27.2 SDK headers (`AVFAudio.framework/Headers/
AVAudioSession.h`, `AVAudioSessionRoute.h`, `AVAudioSessionTypes.h`). No unknown remains.

## AUD-007-D1: Where the route comes from

- **Decision**: `AVAudioSession.sharedInstance().currentRoute` (`inputs`, `outputs`, each an
  `AVAudioSessionPortDescription` with `portType` and `portName`), read on the main actor when the
  route-change notification arrives and when a source starts.
- **Rationale**: The documented, public source of the active route; it already reflects the change
  when the notification is posted.
- **Alternatives**: `AVRoutePickerView` (a picker, not a reader; out of scope); Core Audio HAL
  properties (macOS only on iOS: not available).

## AUD-007-D2: Port-type mapping by raw string

- **Decision**: Map `portType.rawValue` strings to a platform-neutral `RoutePortKind` in pure Swift
  (so the mapping is tested on Linux), and verify on the simulator that each `AVAudioSession.Port`
  constant maps to the intended kind. Values not listed (Virtual, PCI, FireWire, DisplayPort, AVB,
  Thunderbolt, Continuity Microphone, media device extension, anything new) map to `other`
  (output) or `otherInput`.
- **Rationale**: Linux CI cannot import AVFAudio; the simulator test pins the raw values to the
  SDK's constants, so a renamed constant fails a test instead of silently showing "other".
- **Alternatives**: Switch on `AVAudioSession.Port` directly (iOS only; untestable on Linux).

## AUD-007-D3: Names

- **Decision**: Use `portName` as given. An empty name falls back to a generic name per kind
  ("Speaker", "Headphones", "Bluetooth device", …). Several ports are joined with ", " in iOS's order.
- **Rationale**: AUD-007-R5: never invent device names; iOS's names are already localized and
  user-facing (for example the name the user gave their AirPods).

## AUD-007-D4: Observing changes

- **Decision**: A main-queue observer of `AVAudioSession.routeChangeNotification` (object: the shared
  session) reading `AVAudioSessionRouteChangeReasonKey`, mapped to `AudioRouteChangeReason` (raw
  values 0-8 as in the header; unknown values map to `.unknown`). The observer's center and object
  are parameters, like AUD-014's `AudioSessionObserver`.
- **Rationale**: Same proven pattern; tests post to a private center.

## AUD-007-D5: One shared pause rule

- **Decision**: `AudioRouteChangeReason.pausesInAppPlayback` (true only for `oldDeviceUnavailable`)
  is the single definition. `AudioSessionSignal.parse` uses it to produce `.outputRouteLost`, and the
  explanation uses it (with "not held by the user") for "— paused".
- **Rationale**: Clarification 4: the two observers receive the notification in an unspecified
  order, so the explanation must not read the transport after the fact.

## AUD-007-D6: When to explain

- **Decision**: Explain only when the shown direction's ports changed and the reason is not
  `categoryChange`. Lost port first (reason `oldDeviceUnavailable` with a port gone), then "none
  left", then "switched" (a new primary port, or a port added). Otherwise nothing.
- **Rationale**: Category changes are the app's own session setup at a source start (for example
  Microphone `.record` → In-App Playback `.playback`); explaining them would be noise.

## AUD-007-D7: Microphone mode shows the input

- **Decision**: See Clarification 1. Microphone's session uses the `.record` category, whose route
  has no outputs; the indicator shows inputs in that mode.

## AUD-007-D8: Accessibility

- **Decision**: The indicator is one accessibility element with label "Audio output: <names>" or
  "Audio input: <names>" and identifier `routeIndicator`; the explanation is a text with identifier
  `routeExplanation`, announced with `UIAccessibility.post(notification: .announcement, …)` unless it
  is the "— paused" case (Clarification 3).

## AUD-007-D9: UI test hook

- **Decision**: `-uitestFakeRoutes` (DEBUG only) swaps the provider for a settable fake starting at
  the built-in speaker and shows Debug buttons that set a route and post the real route-change
  notification with a reason (wired in/out, Bluetooth in/out, AirPlay). AUD-014's backend reacts to
  that real notification exactly as on a device.
- **Rationale**: The simulator's route never changes; the existing `-uitestSessionEvents` panel
  (AUD-014) shows the pattern.
