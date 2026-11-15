# Data Model: OSC-006 OSC Bundles

- **OSCBundleTiming** (value): `onTimeTolerance` 20 ms, `maximumLateness` 1 s, `horizon` 10 s, `capacity` 256
  (nanoseconds / messages). Fixed default; injectable for tests.
- **OSCWallClock** (value): `now() -> OSCTimeTag` (NTP). `.system`, or a fake in tests.
- **OSCTimeMapping** (value): `monotonicNow`, `wallNow`; `due(for: OSCTimeTag) -> UInt64?` (nil for
  "immediately"); `nanoseconds(from:to:)` signed difference.
- **OSCScheduledMessage** (value): `message`, `due` (monotonic ns), `sequence` (UInt64).
- **OSCBundleSchedule** (value): min-heap of scheduled messages; `count`, `earliestDue`, `insert`, `takeDue(now)`
  (ascending (due, sequence)), `removeAll()`.
- **OSCReceiverCounters** (+): `scheduled`, `lateApplied`, `lateDropped`, `beyondHorizon`, `scheduleOverflow`
  (messages). Memory only.
- **OSCDispatchOutcome** (+): `.scheduled`, `.dropped(OSCBundleDrop)` with `tooLate`, `beyondHorizon`, `queueFull`.

State: a scheduled message is pending until it is due (dispatched once) or the schedule is cleared (receiver stop or
start, `clearScheduled()`).
