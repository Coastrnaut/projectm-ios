# Data Model: UIX-015

## PermissionExplainerPolicy (pure)
- `shouldExplain(status: PermissionState?, explained: Bool, suppressed: Bool) -> Bool`
  = `!suppressed && !explained && status == .notDetermined`.
- `isSuppressed(arguments:environment:harness:) -> Bool` (UIX-015-R13).
- Keys: `cameraExplainedKey = "permission.explained.camera"`, `localNetworkExplainedKey =
  "permission.explained.localNetwork"`; microphone has none (Clarifications).

## PermissionExplainerCoordinator (@MainActor, @Observable)
| Field | Meaning |
|---|---|
| `pending: AppPermission?` | the explainer on screen |
| action (ignored by observation) | the pick to perform on Continue |

Transitions: `request(p, status, perform)` → explain (pending = p) or perform at once;
`continuePending()` → flag set, pending nil, perform; `notNow()` → pending nil, nothing stored;
`markExplained(p)`; `reset(defaults)` (test reset).

## PermissionNotice (extended)
- `fallback: String?` — what still works (camera denied/restricted, local network denied).
- `offersDismiss: Bool` — camera denied/restricted only.

## Camera notice dismissal (AppCoordinator, memory)
- `cameraNoticeDismissed: Bool`; reset when the Camera visual is created or released.
