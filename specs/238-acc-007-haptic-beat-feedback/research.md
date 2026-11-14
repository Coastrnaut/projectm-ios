# Research: ACC-007 Haptic Beat Feedback

- **ACC-007-D1 Haptic API**: `UIImpactFeedbackGenerator` (styles light, medium, heavy; `impactOccurred(intensity:)`)
  is the public, battery-friendly API for one transient tap. Core Haptics (`CHHapticEngine`) would add custom
  patterns and an engine lifecycle (reset and stopped handlers) that one tap does not need. Only
  `CHHapticEngine.capabilitiesForHardware().supportsHaptics` is used, to disable the switch on iPads and the
  simulator. Rejected: Core Haptics players (complexity, engine restarts in the background).
- **ACC-007-D2 Event source**: SHOW-011's `TempoCoordinator` already reads one bus subscription app-wide (own
  pipeline under projectM, the native host's otherwise) with PERF-011's lifecycle. A per-event callback on
  `TempoSubscriptionReader.poll(onEvent:)` reuses it. Its 250 ms poll would add up to 250 ms latency, so the
  poll runs every 40 ms while the observer is set (the indicator is time-based, ANL-006, so faster polls do not
  change its states). Rejected: a second pipeline (two readers of the one-consumer analysis tap), a subscription
  per native host (five hosts, nothing under projectM).
- **ACC-007-D3 Limits**: 150 ms minimum interval (two pulses cannot blur into a buzz; a 200 BPM beat is
  300 ms), at most 4 in any 1 s (the felt rate of 240 BPM), at most 180 in any 60 s (3 per second on average:
  continuous fast kicks are trimmed while ordinary beats up to 180 BPM pass). Times are the events' bus times, so
  a stream gives the same pulses on every run. Stale events (> 200 ms after their bus time at delivery) are
  dropped. The last 180 pulse times live in a fixed ring allocated once.
- **ACC-007-D4 Downbeats**: no downbeat detection exists (MOD-017 Bar counts 4 beats from an anchor). The gate
  counts confident beats from each session marker; beats 1, 5, 9… are downbeats. Throttled or stale beats
  still count, so the bar position never shifts.
- **ACC-007-D5 Sensory safety**: ACC-012-R9 asks future haptics to read the profile. Intensity is the clamp's
  intensity limit; Strict's 0.25 or lower plays nothing (a strict profile means no surprise stimuli). The flash
  part (and Reduce flashing alone) does not apply, mirroring ACC-001-R5.
- **ACC-007-D6 Conditions**: app active (`UIApplication.applicationState == .active`), Low Power Mode off
  (`ProcessInfo.isLowPowerModeEnabled`, read per event), hardware support (read once). All are injected for
  tests. While a condition blocks, events still reach the gate as `playable: false`, so downbeats keep counting.
- **ACC-007-D7 UI test on the simulator**: the simulator has no haptics, so the switch would be disabled.
  DEBUG `-uitestHapticsAvailable` reports haptics as available; the fake does not play anything on the
  simulator anyway (the system generator is a no-op there).
