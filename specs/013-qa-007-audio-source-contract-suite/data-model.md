# Data Model: QA-007 Audio source contract suite

Test-only types in `Packages/CaptureKit/Tests/CaptureKitTests/`. Nothing is persisted.

## SourceConfiguration (enum, 5 cases)

`systemAppCapture` · `microphone` · `inAppReference` · `inAppFile` · `inAppTestSignal`

| Field | Meaning |
|---|---|
| mode | `AudioSourceMode` the configuration must be labeled with |
| track | In-App Playback only: `.reference`, `.file(<library URL>)`, `.tone(sine-1k fixture)` |
| parameters | `SourceParameters` (below) |

## SourceParameters (contract P1 to P7; P8 has its own test)

| Field | Type | Values |
|---|---|---|
| denialReason | StopReason | screenRecordingNotAllowed / permissionDenied / inAppPlaybackFailed |
| policySource | `InterruptionPolicy.Source` | asks the policy for P2 outcomes |
| suspendsForLifecycle | Bool | false for System/App Capture |
| terminalEvent, terminalState, terminalReason | SourceEvent, AudioState, StopReason | P4 |
| resumesOnReturnDuringOpenInterruption | Bool | true for Microphone only (P5) |
| resumeRechecksPermission | Bool | true for Microphone only (P6) |
| forwardsIdleStop | Bool | true for System/App Capture only (P7) |

## ConformanceBackend (protocol, one fake per seam)

| Member | Meaning |
|---|---|
| sessions | `SeamSessions`: the shared `OrderLog` ("start <mode>", "stop <mode>", "idle stop <mode>", "refused <mode>", "pause <mode>", "resume <mode>") and the counters |
| startCalls, liveStops, idleStops, pauseCalls, resumeCalls | counters (a live stop ends a session; an idle stop finds none) |
| liveSessions | sessions started and not stopped (must never exceed 1) |
| maxLiveSessions | the highest `liveSessions` ever reached |
| denyNextStart | Bool: the next start fails with the configuration's denial |
| deliver(amplitude:seconds:) | writes 48 kHz stereo Float32 into the live session's sink; no-op without one |
| send(_:) | the live session's event callback |
| sendLate(_:) | the callback kept from the last ended session |
| hasSink | whether the fake holds a sink (only while a session is live) |

## ContractRig

The real `CaptureManager` (no analysis timer, `ManualClock`) over the three real adapters, each on
its conformance backend, all backends sharing one `OrderLog`. Helpers: `play(amplitude:seconds:)`
(deliver in 10 ms chunks, advance the clock, step the analysis), `settle(_:)` (send a
`formatChanged` marker and wait for its log entry), `waitFor(_:_:)` (condition with a 5 s ceiling),
and `assertTransitionsAllowed()` (R8, called before every new attempt and at the end).
