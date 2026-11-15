# Data Model: OSC-004 OSC Learn

- **OSCLearnSession<Target>** (memory): `target: Target?`, `deadline: UInt64` (monotonic ns);
  `timeoutNanoseconds = 10_000_000_000`. Idle → learning (start) → idle (bound, timed out, cancelled).
- **OSCLearnOutcome<Target>**: `.bound(address, target)`, `.timedOut(target)`, `.cancelled(target)`.
- **Dispatcher learn capture** (memory, under the dispatcher lock): `armed: Bool`, `handler`, one captured address
  handed out after the lock is released.
- **OSCLearnResolution**: `.added`, `.replaced(previous: ParameterID)`, `.alreadyBound`, `.full`, `.unavailable`.
- **Learned route**: `OSCRouteAlias(address, parameter)` stored as `<address>=<parameter ID>` in `settings.osc.aliases`.
