# Data Model: PERF-010 Crash-Safe Session Recovery

## SessionRecord (UserDefaults, app domain)

| Key | Type | Meaning |
|---|---|---|
| `session.recovery.open` | Bool (absent = false) | A session is running in the foreground. |
| `session.recovery.sessionsSinceReopen` | Int (absent = none) | Sessions since the user tapped Reopen (0 = that session). |
| `session.recovery.heldVisual` | String (VisualChoice raw value, absent = none) | The visual to reopen while an offer is unanswered. |

## LaunchDecision

`clean` | `suppressed` (DEBUG test harness) | `abnormal(crashLoop: Bool)`.

Transition at launch (pure, `SessionRecoveryPolicy.launch(record:)`):

| open | sessionsSinceReopen (prev) | decision | new sessionsSinceReopen |
|---|---|---|---|
| false | none | clean | none |
| false | p | clean | p+1, none if p+1 ≥ 2 |
| true | none | abnormal(crashLoop: false) | none |
| true | p < 2 | abnormal(crashLoop: true) | none |
| true | p ≥ 2 (not stored) | — | — |

After the decision, `open` = true. Background/terminate → `open` = false; foreground → true.
Reopen → `sessionsSinceReopen` = 0, `heldVisual` removed. Start fresh → `heldVisual` removed.

## RecoveryOffer (in memory, SessionRecoveryCoordinator)

| Field | Type | Meaning |
|---|---|---|
| `isPresented` | Bool | The card is shown. |
| `canReopen` | Bool | A committed scene exists and not a crash loop. |
| `crashLoop` | Bool | The "closed unexpectedly again" text. |
| `oscTurnedOff` | Bool | OSC had been on; the card says it was turned off. |

States: `none` → (abnormal launch) `pending` → `reopened` | `startedFresh`.
