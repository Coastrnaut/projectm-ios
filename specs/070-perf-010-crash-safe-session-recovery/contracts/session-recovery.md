# Contract: Session recovery (PERF-010)

## C1 Launch order (AppCoordinator.init)

1. `-uitestResetNotice` (DEBUG and Release, as today) also removes the three `session.recovery.*` keys.
2. `AppSettings` is read.
3. `SessionRecoveryCoordinator` decides (`clean`, `suppressed`, `abnormal(crashLoop:)`) and marks the
   session open.
4. Abnormal: `oscTurnedOff = settings.oscEnabled`; `settings.oscEnabled = false`; held visual =
   stored `heldVisual` ?? `settings.visual`; scene settings set to defaults.
5. `OSCReceiverCoordinator` is created (abnormal: the toggle is off, nothing listens).
6. Clean/suppressed: SCN-002 restore and apply as today. Abnormal: no restore; `canReopen` = a valid
   committed scene loads (read-only) and not a crash loop.

## C2 Card (SessionRecoveryOfferCard)

- Identifier `sessionRecoveryOffer`; title "projectM closed unexpectedly." (crash loop:
  "projectM closed unexpectedly again."); body "Reopen your last scene or start fresh." (no scene or
  crash loop: "Starting with a fresh scene."); OSC line "OSC was turned off." (`sessionRecoveryOSC`).
- Buttons: `sessionRecoveryReopen` "Reopen last scene" (only when `canReopen`),
  `sessionRecoveryStartFresh` "Start fresh".
- Shown on the chooser (top inset) and the visualizer (top status stack); never modal; posted to
  VoiceOver as an announcement once.

## C3 Reopen / Start fresh

- Reopen: `sceneAutosave.restore` → `SceneAutosaveCapture.apply`, text; `settings.visual` = held
  visual; `sessionsSinceReopen` = 0; held visual removed; card dismissed. OSC and the camera unchanged.
- Start fresh: held visual removed; card dismissed.

## C4 DEBUG probe

Static text `sessionRecovery` (with `-uitestDiagnostics`), value
`decision=<clean|suppressed|abnormal|crashLoop> offer=<none|pending|reopened|fresh> osc=<listening|off>`;
`osc` is `listening` iff the receiver's state is `.listening` or `.starting`.
