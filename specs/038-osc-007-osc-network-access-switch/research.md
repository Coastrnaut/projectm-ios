# Research: OSC-007 OSC Network Access Switch

## OSC-007-D1: What drives the badge

- **Decision**: `OSCReceiverState.listening(port)` only (`OSCReceiverCoordinator.state`, copied to the
  main actor from the receiver's state handler).
- **Rationale**: the receiver enters `listening` only on the transport's `.ready`, which
  `NetworkDatagramTransport` reports from `NWListener.State.ready`; it leaves it synchronously on
  `stop()` (`stopping`). So the badge disappears the moment Stop is tapped and never claims a socket
  that is not open (Constitution IV).
- **Alternatives**: the toggle (`settings.oscEnabled`) — rejected: on but failed or backgrounded
  would show "listening" falsely. Showing `starting` too — rejected: no socket is ready yet.

## OSC-007-D2: Stop

- **Decision**: `stopFromBadge()` calls `setEnabled(false)` (writes `settings.osc.enabled = false`,
  then `receiver.stop()`), and posts a VoiceOver announcement "OSC off" from the view.
- **Rationale**: one path for the toggle and Stop, so Settings shows off and the listener closes with
  OSC-001's confirmed cancel; no new state.
- **Alternatives**: stopping the receiver without writing the setting — rejected: it would reopen on
  the next foreground return, and Settings would show the toggle on.

## OSC-007-D3: Placement and the CAM-012 merge

- **Decision**: visualizer — the first row of the top `VStack` that holds the banners, centred; chooser
  — `.safeAreaInset(edge: .bottom)` on the chooser's `NavigationStack`.
- **Rationale**: the top of the visualizer is free in the middle (performance overlay top-right, debug
  panels top-left); CAM-012's plan places its "Camera on" badge "at the top of VisualizerView", so both
  go in the same stack. The expected merge conflict is one hunk at the top of that `VStack`; resolve it
  by keeping both badges (OSC first, then camera, or an `HStack` of the two).
- **Alternatives**: inside the controls — rejected: hidden with the controls (R2). Bottom of the
  visualizer — rejected: collides with the controls and the source indicator.

## OSC-007-D4: Proving "toggle on/off changes socket state" in the app

- **Decision**: an app unit test with `OSCReceiver.system()` behind the coordinator, on a free
  high port: `setEnabled(true)` → poll the main-actor state until `listening(port)`; `setEnabled(false)`
  → poll until `off` (reported only after the listener's `.cancelled`); then an independent second
  receiver binds the same port and reaches `listening`, proving the socket was released. A `failed`
  state on the first start skips the test (sandbox refused), never passes it.
- **Rationale**: test targets may not use the Network framework (check_compliance.py), and the
  debug-only loopback sender is internal to the package; the bind-again probe needs neither. The
  package's `OSCLoopbackIntegrationTests` already proves packets flow and stop at the receiver level.
- **Port choice**: a pseudo-random port in 49152-65000 (the ephemeral range, unlikely in use); on
  `portInUse` the test skips.
- **Alternatives**: making `OSCLoopbackSender` public — rejected: widens the package API for one test.

## OSC-007-D5: Fresh install across a foreground cycle

- **Decision**: unit test on an empty `UserDefaults` suite with a logging fake transport:
  construct, `sceneBecame(active: false)`, `sceneBecame(active: true)` → zero transport creations.
- **Rationale**: complements `OSCReceiverCoordinatorTests.testOffByDefaultOpensNothing` (construction
  only) without duplicating it.
