---
name: maintain-autotester-doc
description: "Keep docs/autotester.md (device test automation guide and lessons learned) built, managed and up to date"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-16T01:10:53.763Z
---

On 2026-11-15 the owner asked to document every lesson learned and how device testing is automated in a notes file
"for steering other repos and future work on this repo", then: "remember to build this file and keep it updated
docs/autotester.md. remember to manage that file and update it. also commit to claude".

**Why:** the device-automation knowledge (wireless devicectl, app-hosted package tests, typed launch settings, clean
starts, music fixture, screenshot checks, what still needs a person) is hard-won and must survive sessions and travel
to other repositories.

**How to apply:**
- `docs/autotester.md` is the single maintained file (the owner first called it `docs/autotesting.md`; the latest
  name won). Update it in the same commit as any change to device automation (DeviceTests.yml, DeviceUITests,
  run_device_matrix.py, AutomationRunner modes, fixtures) and whenever a run teaches something new.
- Keep it current: the pieces table, the run commands, lessons learned (add, correct, never let it go stale), what
  still needs a person, and the guide for another repository.

Related: [[device-runs-never-idle-unexplained]], [[unattended-autonomous-device-stage]].
