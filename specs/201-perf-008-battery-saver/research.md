# Research: PERF-008 Battery saver profile

## PERF-008-D1 Where the budget lives
- Decision: `PowerBudget` beside `QualityGovernor` in Packages/Rendering; a process-wide `PowerProfileState`.
- Rationale: seven frame loops (two in packages: ANGLE, GLES) already call `QualityGovernor.current()`; giving
  `current()` the profile reaches all of them without threading a new dependency through every host.
- Alternatives: pass the profile into each host (7 call sites, two packages' public API) — rejected as wider.

## PERF-008-D2 Composition with the thermal governor
- Decision: per-value minimum (`min(fps)`, `min(scale)`), floor 30 fps kept.
- Rationale: "the governor can lower further but never raise above the profile cap"; caps do not compound (critical
  0.75 with saver 0.75 stays 0.75).

## PERF-008-D3 Battery saver values
- Decision: 30 fps, 0.75 scale, no background warm-up.
- Rationale: the FR-049 floor and the critical-state scale are values the app already runs on D1-D3 (Gate 3,
  T101); no new quality tier to validate. Warm-ups render presets on a second GPU context (SC-104) and decode media
  ahead (PERF-005): pure background energy.

## PERF-008-D4 Change propagation
- Decision: `PowerProfileState.didChangeNotification` posted on the main thread; every loop observes it with the
  thermal/power notifications (`QualityGovernor.changeNotifications`).
- Rationale: the loops already re-read `current()` and update `preferredFrameRateRange` and the drawable scale
  without restarting (FR-049 path).

## PERF-008-D5 Audio isolation
- Decision: the setting has no reference to `CaptureManager`, the transport or the sources; the acceptance test
  snapshots a real `CaptureManager` with a fake source before and after switching and compares.

## PERF-008-D6 Instrumentation
- Decision: `DiagnosticsLog.powerProfile(_:)` emits an os_signpost event ("Power profile", profile name) on each
  change; frame time comes from the existing PERF-001/PERF-007 overlay lines and Instruments' Metal counters on D1.
  MetricKit is not added (no payload handling in the app; it would be a new data path) — not appropriate here.
