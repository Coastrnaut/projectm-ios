# Quickstart: OSC-006 OSC Bundles

1. Package tests (host, about 1 s):
   `swift test --package-path Packages/PerformanceControl --filter 'OSCBundleSchedule|OSCDispatcher|OSCLoopback'`
   Expect: the reverse-order pair applies at t+10 ms then t+20 ms; ties, immediate, late, horizon, capacity, nested
   and stop cases pass; the loopback bundle applies no earlier than its due time.
2. App test on "OSC6 iPhone 17": `OSCReceiverCoordinatorTests/testScheduledBundleChangesTheParameterAtItsTime`.
3. `{device}` D1 with a LAN sender whose clock is network-synced: send a bundle 500 ms ahead to
   `/projectm/test`; the test value changes about half a second later; a bundle 30 s ahead never applies.
