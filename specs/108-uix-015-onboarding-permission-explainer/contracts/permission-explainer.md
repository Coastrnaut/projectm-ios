# Contract: Permission explainer (UIX-015)

## C1 Explainer sheet
| Element | Identifier | Content |
|---|---|---|
| Container | `permissionExplainer.<camera|localNetwork>` | — |
| Title | `permissionExplainerTitle` | catalog `name` ("Camera", "Local Network") |
| Body | `permissionExplainerText` | catalog `usageDescription` (= Info.plist text) |
| Fallback | `permissionExplainerFallback` | catalog explainer fallback (research D6) |
| Note | — | "iOS asks next. You can change this later in Settings." |
| Continue | `permissionExplainerContinue` | "Continue" |
| Not now | `permissionExplainerNotNow` | "Not now" |

## C2 Decision table
| Status | Explained | Suppressed | Result |
|---|---|---|---|
| notDetermined | no | no | explainer |
| notDetermined | yes | — | go ahead (iOS asks if it still can) |
| granted / denied / restricted / nil | — | — | go ahead (no explainer) |
| any | — | yes | go ahead |

## C3 Notices
| Notice | Fallback (`<prefix>NoticeFallback`) | Dismiss (`<prefix>Dismiss`) |
|---|---|---|
| Camera denied / restricted | "Showing the spectrum only." | yes, per attempt |
| Camera no camera / interrupted / failed | none (text already says it) | no |
| Local network denied | "OSC control is unavailable; everything else works as usual." | no (inline in Settings) |
| Microphone denied banner | unchanged (Choose source) | unchanged |

## C4 Storage
`permission.explained.camera`, `permission.explained.localNetwork` (Bool), cleared by `-uitestResetNotice`,
listed in `scripts/run_device_tests.py` `ALLOWED_KEYS`.
