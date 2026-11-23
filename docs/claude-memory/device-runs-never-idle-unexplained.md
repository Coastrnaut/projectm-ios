---
name: device-runs-never-idle-unexplained
description: "During device runs, keep each device working until every case passes; watch each run with device_watch.py and say at once when a device is idle or hung"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-15T19:50:53.061Z
---

On 2026-11-15 the owner saw D1 and D2 doing nothing and asked why they had stalled. Nothing had hung: each
device's queued QA-011 cases had finished, but cases were still short of a pass (`thresholds` waiting for a PERF-012
report, `xctest-angle-layer` without a device host), and I had neither started the next fix nor said clearly that
the devices were idle. The owner said: "do not start d3 until d1 and d2 have passed successfully … learn the lesson".

**Why:** the owner is at the devices and judges progress by what the devices do. A finished run is not a passed
device, and an idle device with no stated reason looks like a stall.

**How to apply:**
- A device is done only when every one of its cases passes (or is blocked on something only the owner can do, named
  as such). Do not start the next device until then.
- When a device goes idle, the first line of the update says so: "D1 idle: N passed; X, Y not passing because …;
  next: …" — then start the next action at once (fix, rebuild, rerun) instead of waiting.
- When asked whether something stalled, check first (`xcrun devicectl device info processes`, `pgrep -fl
  "run_device_matrix|xcodebuild test"`, the run logs) and answer with what is actually running.
- Prefer automating a case's missing input over leaving it for a hand step (the PERF-012 report got an automation
  mode for the QA-010 judge).

**Amended 2026-11-23** ("d1 and d3 both look hung up on a test on the devices, learn the lesson and remember it"): D3's
run had been silent 15 minutes before the runner's watchdog stopped it, and D1's queue had ended 15 minutes earlier with
the app's last screen still up. My background waiters reported only when a whole queue ended, so I noticed neither.
- Alongside every device run, keep `python3 scripts/device_watch.py --devices <the ones running>` going in the
  background. It exits (and wakes me) the moment a device's log is silent for 5 minutes or a device has no
  `xcodebuild test` running. Then check it (screenshot with `devicectl device capture screenshot`, the log's last
  steps), say "D3 hung in <test>" or "D1 idle", fix or restart it at once, and start the watcher again.
- Never rely on a waiter that only reports at the end of a queue, and never leave a device's queue empty: queue the
  next run before the current one ends.

Related: [[never-stop]], [[no-idle-waits-on-ci]].
