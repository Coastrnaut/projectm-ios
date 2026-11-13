# Data Model: SHOW-014 Emergency Blackout

No stored data (FR-065). Two derived rules on OUT-010's `OutputBlackout.Phase`
(`Packages/PresentationLifecycle`):

| Phase | `offersEmergencyBlackout` | `offersRestore` | B key does |
|---|---|---|---|
| `live` | true | false | black out |
| `blackedOut` | false | true | restore (fade, or wait for the spacing) |
| `restoreWaiting` | false | false | nothing |
| `fadingIn` | true | false | black out |

Invariant: the two rules are never both true (one key command at a time).

The emergency button is shown when the screen is the visualizer (it lives in `VisualizerView`) and
`offersEmergencyBlackout` holds. Its action is `setBlackout(true)` on the shared
`ExternalDisplayCoordinator`; the transitions are OUT-010's (`specs/051-.../data-model.md`).
