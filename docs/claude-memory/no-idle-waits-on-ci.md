---
name: no-idle-waits-on-ci
description: "Never stop work waiting on CI; monitor it in the background, keep working, fix issues when it completes"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-13T14:03:18.401Z
---

Never stop work waiting on CI: keep working while CI runs, monitor it in the background, and fix any issues when it completes.

**Why:** On 2026-11-13 the owner asked "is something hung, check and fix it, remember the lesson learned from this and write it to claude". Nothing was hung, but the run had stalled: after a push I scheduled a single CI read 50 minutes later, CI's Linux job had already failed at minute 5 (a test used `fflush(stdout)`, which Swift 6 rejects on Linux), integrated work (ANL-004) was held back waiting for that run, and one of the two agent slots stood empty. Holding pushes back was itself caused by `cancel-in-progress: true`: with 50-90 minute macOS jobs, every push cancelled the previous run.

The same day the owner added: "remember not to stop work waiting on ci, keep working wihile ci runs and monitor it in the background, when its complete fix any issues, remember this and write it to claude".

**How to apply:**
- After every push, start `python3 scripts/autonomous/ci_monitor.py --sha <sha>` with the shell's background mode (one `gh` call every 5 minutes; it prints each job as it finishes and exits when the run is complete). Then keep working: never end a turn or sleep just to wait for CI, and never use `gh run watch` (it exhausted the API limit).
- When the monitor exits (or reports a failed job early), read the failed job's log once and fix the cause and its whole class, then push and monitor again.
- Push locally verified work right away (owner rule: don't hold work back for CI). CI on `main` uses `cancel-in-progress: false` since 2026-11-13, so a push never cancels a running run.
- Keep every agent slot busy: when a slot frees, start the next scheduled feature in the same turn instead of waiting for CI or for another agent.
- When something looks stuck, check in this order: running processes and their age (`ps -o etime`), agent worktree commit times, CI job states; then fix the real cause, not just the symptom.
- Fix the whole class behind a CI failure (here: a script test now rejects C stdio globals in package Swift code).
