---
name: no-idle-waits-on-ci
description: "Never sit idle on one long CI wait; read fast jobs early, push verified work at once, keep agent slots busy"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-13T14:03:18.401Z
---

Never let the work stall behind one long wait on CI.

**Why:** On 2026-11-13 the owner asked "is something hung, check and fix it, remember the lesson learned from this and write it to claude". Nothing was hung, but the run had stalled: after a push I scheduled a single CI read 50 minutes later, CI's Linux job had already failed at minute 5 (a test used `fflush(stdout)`, which Swift 6 rejects on Linux), integrated work (ANL-004) was held back waiting for that run, and one of the two agent slots stood empty. Holding pushes back was itself caused by `cancel-in-progress: true`: with 50-90 minute macOS jobs, every push cancelled the previous run.

**How to apply:**
- After a push, read CI twice with single calls: once at about 10 minutes (docs and Linux jobs finish by then), once when the macOS jobs should be done (about 55 minutes). Never one long wait, never a polling loop.
- Push locally verified work right away (owner rule: don't hold work back for CI). CI on `main` uses `cancel-in-progress: false` since 2026-11-13, so a push never cancels a running run.
- Keep every agent slot busy: when a slot frees, start the next scheduled feature in the same turn instead of waiting for CI or for another agent.
- When something looks stuck, check in this order: running processes and their age (`ps -o etime`), agent worktree commit times, CI job states; then fix the real cause, not just the symptom.
- Fix the whole class behind a CI failure (here: a script test now rejects C stdio globals in package Swift code).
