# Contract B1: OSC bundle scheduling (OSC-006)

`OSCDispatcher.handle(datagram)` for a well-formed bundle:

1. Apply every pending message whose due time has passed (ascending due, then sequence).
2. Read `mapping = (clock.now(), wallClock.now())` once.
3. For each message, depth-first: effective tag = max over its enclosing bundles' tags; `due = nil` when the
   effective tag is "immediately", else `mapping.due(tag)`; assign the next sequence number.
4. Classify: `due ≤ now` → late by `now − due`: ≤ tolerance → apply now; ≤ max lateness → apply now and count
   `lateApplied`; else `.dropped(.tooLate)` and count `lateDropped`. `due − now > horizon` →
   `.dropped(.beyondHorizon)`. Otherwise future.
5. Apply-now messages in (due, sequence) order through `apply(message:)`.
6. Future messages: if `pending + n > capacity` all n are `.dropped(.queueFull)` (`scheduleOverflow`), else each
   is `.scheduled` (`scheduled` += n).
7. Outcome `.bundle([...])` in depth-first packet order; arm a wake-up for the earliest due time if none is armed
   for it or earlier.

`flushScheduled()` (wake-up): apply every due message through `apply(message:)`, count it like an immediate one,
re-arm, report activity, hand a learn capture to its handler.

`clearScheduled()`: removes every pending message (called by `OSCReceiver.stop()` and on every launch).

Non-bundle messages and a top-level "immediately" bundle behave exactly as before OSC-006.
