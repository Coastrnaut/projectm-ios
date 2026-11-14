# Research: OUT-002 Display Connect Handling

## OUT-002-D1: What hot-plug does today (audit, commit `0d19488e`)

- Events enter `ExternalDisplayCoordinator` from `ExternalDisplaySceneDelegate` (iOS 26 Info.plist
  role `windowExternalDisplayNonInteractive`), `ExternalAccessorySlot` (iOS 27 scene accessory) and
  `UITestExternalDisplay` (DEBUG). `ExternalDisplayRouting` decides the target; `place()` moves the
  visual's own view into the target `VisualSlotView` inside the call.
- The internal session is not recreated: the host, renderer or compositor, engine, preset, scene and
  audio source stay. ANGLE's `MetalLayerView.didMoveToWindow` stops and restarts its display link
  across the move (same instance, counters continue); the Metal hosts guard drawing on
  `view.window != nil`. Camera, Photo, Video and Text hosts ignore the external scene's own
  connect/disconnect notifications (`ExternalDisplayScenes.affectsDeviceVisuals`).
- The move changes the drawable size, so FX-009 trails reset (FX-009-R5: "external display" is a
  listed trigger) and a recording stops with `sizeChanged` (REC-003-R11).
- The blackout already covers every slot first in `place()`, so a new slot is black while blacked out.
- Connection changes are logged, not announced.

Decision: keep OUT-001's move design; add the settle, the recording hold, the announcements, the
seam and counters. Rejected: a mirrored second output (OUT-001-R3, double GPU cost).

## OUT-002-D2: Debounce

Decision: settle connects for 0.3 s with a token per pending connection; the scheduled callback
settles only if the token still matches; a disconnect cancels a pending connection and is otherwise
applied at once. The settle callback runs on the main actor (`Task.sleep`), injected in tests by a
manual scheduler. Rationale: disconnects cannot wait (the window goes away); a token avoids clocks in
the rule. Alternatives: deadline + clock polling (needs a clock, wall-time races); debounce in
`ExternalDisplayRouting` (would delay disconnects too).

## OUT-002-D3: Recording continuity

Decision: a placement hold while `VideoRecordingCoordinator.state == .recording`: the effective target
stays the held one while it is still connected; on release, OUT-001 routing applies. Rationale: no
size change, so REC-003-R11 never fires and trails are untouched. Alternative: scale frames into a
fixed-size recording (new compositor shader path and a spectrum render pass; letterboxed video;
edits to shared hot files). Unavoidable case: the display the recording is on is unplugged; the
recording then stops with REC-003's notice.

## OUT-002-D4: Announcements

Decision: status events X27 "External display connected" (plus " It shows the visualization when the
recording ends." while held) and X28 "External display disconnected", cause system, caption, on a new
`display` announcer lane. Rationale: the `output` lane carries blackout announcements; ACC-004's gate
replaces pending texts per lane, so a connection must not share it.

## OUT-002-D5: Test seam

Decision: `ExternalDisplayEventSink` protocol (connect, resize, foreground, disconnect) adopted by
the coordinator; the DEBUG fake and the unit tests' `FakeDisplayConnector` drive it with real
off-screen windows and slots. The simulator's own external display (`simctl io … screenConfig`) is
not reliable for hot-plug in a test.
