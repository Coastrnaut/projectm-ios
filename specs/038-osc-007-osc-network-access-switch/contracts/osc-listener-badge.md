# Contract: OSC listener badge (OSC-007)

## Coordinator (`OSCReceiverCoordinator`, main actor)

- `static func listenerBadgePort(for state: OSCReceiverState) -> UInt16?` — the port for
  `listening(port)`, nil otherwise (OSC-007-R2, R3).
- `var badgePort: UInt16?` — `listenerBadgePort(for: state)`.
- `static func badgeText(port: UInt16) -> String` — "OSC listening on port \(port)".
- `func stopFromBadge()` — `setEnabled(false)`; changes nothing else (OSC-007-R4, R5). Idempotent.

## View (`OSCListenerBadge`)

Shown iff `badgePort != nil`.

| Element | Identifier | Label | Value | Hint |
|---|---|---|---|---|
| badge (container, children contained) | `oscListenerBadge` | — | — | — |
| text | `oscListenerBadgeText` | "OSC listening" | "Port N" | — |
| Stop button | `oscStopButton` | "Stop OSC" | — | "Turns off the OSC receiver" |

Visible text: "OSC listening on port N" and a "Stop" button. After Stop, VoiceOver announces
"OSC off" (OSC-007-R7).

## Placement

- Visualizer: first row of the top status stack, above the audio banners, independent of
  `controlsVisible` (OSC-007-R2, R6). CAM-012's badge joins the same stack.
- Chooser: bottom safe-area inset of the chooser's navigation stack.
