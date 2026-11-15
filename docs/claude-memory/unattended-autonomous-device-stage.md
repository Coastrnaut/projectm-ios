---
name: unattended-autonomous-device-stage
description: "Owner wants fully autonomous, unattended operation: investigate, decide with best judgement, act, and keep going without asking"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-15T20:18:24.845Z
---

On 2026-11-15, during the QA-011 device stage, the owner answered a question about three threshold failures with:
"investigate then recommend, and select using your best judgment, operate unattended and fully autonomous remember
this and commit it to claude".

**Why:** the owner does not want to be the bottleneck; questions that I can settle with evidence and judgement stop
the work while they are away.

**How to apply:**
- Investigate, decide, record the decision with its evidence (spec Clarifications, an ADR when it changes a budget or
  a default), act on it, and report it as decided. Do not end a turn on a question I can answer myself.
- This includes test and budget policy (thresholds, measurement method), as long as the change is justified by
  measurement and recorded, never made just to turn a failure green; a real app problem gets fixed in the app or
  stays an honest failure.
- Keep devices working through the whole matrix unattended (start the next device as soon as the previous one
  passes), and keep CI monitored.
- Still the owner's, unchanged: signing; App Store Connect, agreements, banking, purchases, releases; device steps
  that need a person (permission taps, pickers, Airplane Mode, cables, physical sessions B01-B13); amending
  Constitution I or V; destructive git. Batch those into one request and carry on with everything else.

Related: [[best-judgement-on-choices]], [[never-stop]], [[device-runs-never-idle-unexplained]].
