---
name: monitor-posterboard-crashes
description: "Watch for \"PosterBoard quit unexpectedly\" (iOS Simulator) crashes during simulator work and fix them as required"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-13T11:16:59.126Z
---

While running simulator builds and tests, check for PosterBoard crash reports and fix the cause as required, without waiting to be asked.

**Why:** On 2026-11-13 the owner got many "PosterBoard quit unexpectedly" dialogs on the Mac Studio and said "remember to monitor for posterboard crashes and fix as required". PosterBoard is the iOS lock-screen/wallpaper process inside a simulator; the reports land in `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` with parent `launchd_sim`. The first diagnosis found every crash at `-[PRPosterDescriptor _initWithPath:]` during PosterBoard's initial poster-role setup on the iOS 27.2 runtime (24B8117); erasing the affected simulator did not stop it.

**How to apply:**
- After each simulator test run (and at least once per work session), count new `PosterBoard-*.ips` files (`find ~/Library/Logs/DiagnosticReports -name 'PosterBoard-*' -mmin -60`) and, per booted simulator, PosterBoard exits in `xcrun simctl spawn <udid> log show --predicate 'process == "launchd_sim" AND eventMessage CONTAINS "com.apple.PosterBoard"'`.
- If crashes recur, find which simulator and runtime they come from and apply the least intrusive fix (shut down simulators no test needs, erase a corrupted one, avoid a bad runtime build); record what was tried and whether it worked in `docs/test-reports/simulator-posterboard.md`.
- Simulator crashes are never app evidence either way; do not change app code for them unless the app is shown to cause them.
- Do not turn off macOS crash reporting globally without asking the owner: it would hide real crashes too.
