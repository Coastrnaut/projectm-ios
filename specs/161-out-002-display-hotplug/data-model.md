# Data Model: OUT-002 Display Connect Handling

Nothing is stored. All state lives in memory for the app's run.

## HotPlugSettle (PresentationLifecycle, pure)

| Field | Type | Rule |
|---|---|---|
| `interval` | Double (s) | 0.3 in the app, 0 = settle at once (tests of OUT-001 behaviour) |
| `pending` | [PendingConnection] | at most one per display ID |
| `cancelled` | Int | connections cancelled before they settled |

**PendingConnection**: `id`, `geometry` (ExternalDisplayGeometry), `foreground`, `token` (Int, unique per connect).

Transitions: `connect` → pending (new token; a repeat connect replaces the entry) · `update` →
geometry or foreground of a pending entry · `cancel(id)` → removed, `cancelled += 1` · `settle(token)`
→ removed and returned only if the token matches (else nil: stale timer).

## Placement hold (ExternalDisplayRouting extension, pure)

`effectiveTarget(held:)`: `.device` when not visualizing; the held target while it is `.device` or
an external display still connected; otherwise `target`.

## ExternalResourceCounts (app)

`slots` (external slots held), `pending` (unsettled connections), `slotsHoldingVisual` (external
slots with a subview). All 0 after every display has disconnected (OUT-002-R8).

## ExternalDisplayConnectionChange (app)

`.connected(heldByRecording: Bool)`, `.disconnected`: emitted once per settled connect and per
disconnect of a settled display; mapped to status events X27 and X28.
