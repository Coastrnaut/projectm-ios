# Data model: PERF-011 Background resource release

All types are in memory only (spec R14).

## PresentationSignal (enum)

`enteredBackground`, `willEnterForeground`, `locked`, `unlocked`.

## PresentationAvailability (struct)

| Field | Type | Meaning |
|---|---|---|
| `isBackgrounded` | Bool | between `enteredBackground` and `willEnterForeground` |
| `isLocked` | Bool | between `locked` and `unlocked` or `willEnterForeground` |
| `canPresent` | Bool, derived | `!isBackgrounded && !isLocked` |

Initial state: both false. `apply(_:)` returns the new `canPresent`.

| State | enteredBackground | willEnterForeground | locked | unlocked |
|---|---|---|---|---|
| presentable | backgrounded | presentable | locked | presentable |
| backgrounded | backgrounded | presentable | backgrounded + locked | backgrounded |
| locked | backgrounded + locked | presentable | locked | presentable |
| backgrounded + locked | backgrounded + locked | presentable | backgrounded + locked | backgrounded |

## PresentationBoundResource (protocol, main actor, class-bound)

| Member | Meaning |
|---|---|
| `presentationResourceName: String` | stable name for reports, no user content |
| `suspendForPresentationLoss()` | stop work and release what only matters while presenting |
| `resumeForPresentation()` | reacquire and continue |

Both operations must be safe to call when already in the target state (R13); the registry still
calls each at most once per transition.

## Registry entry

| Field | Type | Meaning |
|---|---|---|
| `resource` | weak reference | never keeps the resource alive (R2) |
| `name` | String | copied at registration |
| `suspended` | Bool | suspended by the registry and not yet resumed |

Order: registration order. Uniqueness: object identity.

## PresentationTransitionReport (struct)

| Field | Type | Meaning |
|---|---|---|
| `canPresent` | Bool | state after the change |
| `registered` | Int | live entries |
| `activeBefore` | Int | live entries not suspended before the sweep |
| `activeAfter` | Int | the same after the sweep |

## Renderer state (ANGLERenderer)

Two independent flags: `paused` (user, FR-046) and `presentationSuspended`. The display link exists
only while the view is in a window and `presentationSuspended` is false; it is paused iff `paused`.
The window surface exists only while `presentationSuspended` is false and the view has a size.

## Warm-up state (PresetWarmUpController)

`enabled`, `delay`, `lastRequest` (presets and texture paths), `suspended`, pending delay task.
Worker (`PresetPrewarmer`): idle (no thread, no context) ⇄ running (thread, context, engine,
target); `stop()` returns it to idle and it can run again.
