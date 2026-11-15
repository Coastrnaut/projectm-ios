# Quickstart: OSC-012 Peer Cue Sync

## Package (host, also Linux)

```bash
swift test --package-path Packages/PerformanceControl --filter OSCCueSync
```

Expect: message, leader, follower, packet-loss fixture (50% seeded, first-3 burst, 5 s outage; 60 s heartbeat
bound), dispatcher tap and real-UDP loopback tests pass (loopback skips on Linux).

## App (simulator "OSC12 iPhone 17", iOS 27.2)

`OSCCueSyncCoordinatorTests` (follower show steps to the cue; leader posts through a fake send transport;
unknown cue reported; role key device-only) and `OSCCueSyncUITests` (role Off by default, Lead and Follow
selectable, status shown).

## Two devices `{device}` (OSC-012-T-device)

1. Copy the same show to both (scene pack or backup).
2. On both: OSC receiver on, Only approved devices on, the other device approved (Nearby Devices → Allow).
3. Device A: Send OSC on, destination = B (Use as send destination); Cue Sync → Lead.
4. Device B: Cue Sync → Follow.
5. Step A through cues; B follows within a fraction of a second. Turn B's Wi-Fi off for 10 s, step A, turn it
   back on: B reaches A's cue within about 2 s.
