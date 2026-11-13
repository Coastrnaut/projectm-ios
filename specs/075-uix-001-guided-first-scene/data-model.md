# Data Model: UIX-001 Guided First Scene

## GuidedFirstSceneState (stored, UserDefaults `guide.firstScene`)

| Value | Meaning | Written when |
|---|---|---|
| absent | never offered (install older than this feature, or never saw the notice) | — |
| `pending` | offered, neither finished nor skipped | notice acknowledged and the key was absent |
| `finished` | Play was tapped | Play |
| `skipped` | Skip was tapped | Skip |

Unknown strings read as absent. Removed by `-uitestResetNotice` and with the app.

## GuidedFirstSceneStep (in memory)

`welcome → sound → visual → look → play` (5 steps, index 0-4). `next()` stops at `play`; `back()`
stops at `welcome`. `canGoBack` is false only on `welcome`. Skip is available on every step.

## GuidedFirstSceneDraft (in memory)

| Field | Type | Default | Rule |
|---|---|---|---|
| visual | GuidedVisual (`circularSpectrum`, `linearSpectrum`, `text`) | `circularSpectrum` | maps 1:1 to `VisualChoice`; never Camera, Photo, Video or projectM |
| glow | Bool | true | applied only for the spectra |
| message | String | "Hello" | applied only for Text, through `TextOverlayCoordinator.setMessage` (its sanitizer and limit) |

A new session (launch offer or Settings row) starts at `welcome` with the defaults; Back keeps the
draft.

## Launch rule

`offersAtLaunch(state, recoveryPending, suppressed)` = `state == pending && !recoveryPending &&
!suppressed`. `suppressed` = DEBUG/automation build && harness launch && no `-uitestGuidedFirstScene`.
