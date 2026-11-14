---
name: never-stop
description: "Owner rule: during the autonomous roadmap run, never stop or end work under any circumstances; always keep the next step going"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-14T04:50:14.166Z
---

Never stop the autonomous roadmap run under any circumstances (owner, 2026-11-14: "keep going, remember not to stop under any circumstances, write this to claude").

**Why:** the owner wants continuous progress toward device testing; turns that ended with work merely queued (waiting on a test batch, an agent, or CI) were idle time.

**How to apply:** every turn ends with work in flight: agent slots filled (up to the scheduler's concurrency and the 10-agent cap), the next integration or test batch running, CI monitored in the background. When blocked on one thing (a long test batch, a merge, CI), start the next independent thing instead of waiting. Never end a turn just to report. Problems (failures, budget overruns, conflicts) are fixed or handed to an agent, not left for the owner. Owner-only items (signing, App Store Connect, device steps needing a person, destructive git) are still the owner's: note them and carry on with everything else. Related: [[no-idle-waits-on-ci]], [[best-judgement-on-choices]], [[short-tests]].
