# Research: OSC-006 OSC Bundles

- **OSC-006-D1 Time tag mapping.** Decision: per datagram, `due = monotonicNow + (tag − wallNow)`, the difference
  taken as a signed 32.32 fixed-point value (`Int64(bitPattern: tag &- wall)`) and converted to nanoseconds with
  the seconds clamped to ±10⁶. Rationale: one read of each clock at receipt; wall-clock jumps never move scheduled
  messages; the signed wrap-around difference is correct across the 2036 NTP era. Alternatives: a persistent
  offset estimated over time (needs a sync protocol; out of scope), a user offset setting (skipped: conservative,
  no new key).
- **OSC-006-D2 Wall clock.** Decision: `OSCWallClock` injected like `OSCMonotonicClock`; `.system` reads
  `Date().timeIntervalSince1970` + 2 208 988 800 s. Alternative: `clock_gettime` (needs per-platform imports).
- **OSC-006-D3 Nested tags.** OSC 1.0: a contained bundle's tag must be ≥ its container's. Effective tag =
  max(inner, outer) compared as NTP values, so an inner "immediately" (1) takes the outer tag.
- **OSC-006-D4 Late policy.** Fixed constants in `OSCBundleTiming.default` (tolerance 20 ms, max lateness 1 s,
  horizon 10 s, capacity 256); tests inject others. Not a user setting.
- **OSC-006-D5 Overflow.** Drop the newest (the incoming datagram's whole future part) so earlier cues survive a
  flood; per-datagram atomic so a bundle is never half scheduled.
- **OSC-006-D6 Horizon.** Reject, never clamp.
- **OSC-006-D7 Where limits apply.** Datagram limits and the allow list at receipt (before decoding, unchanged);
  per-target limit, routes, policy and learn at dispatch through `apply(message:)`.
- **OSC-006-D8 Wake-up.** Reuse `OSCFlushScheduler` (a detached sleeping task in the app, manual in tests). One
  armed wake-up for the earliest due time; an earlier arrival arms another; a stale wake-up finds nothing due.
  Every `handle` first applies due messages, so a late timer never reorders values. Not the frame clock: values
  land in the store on the receiving side like every OSC value, and the app reads them on its gated refresh.
- **OSC-006-D9 Ordering structure.** A binary min-heap on (due, sequence); the sequence is a dispatcher-wide
  counter incremented per message in depth-first order, so ties keep arrival order.
