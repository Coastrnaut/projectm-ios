---
name: push-ci-standing-approval
description: Owner gave standing approval to push to origin/main and run CI without asking
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8b68db4f-77f8-47db-a62d-08b04ae70dff
  modified: 2026-11-09T02:46:08.334Z
---

Push to origin/main and let CI run without asking first; then check the run's result.

**Why:** The owner said (2026-11-08) "you have my standing approval to push and run ci, dont ask anymore". Also recorded in CLAUDE.md Conventions.

**How to apply:** After committing finished work, push and watch CI. Keep `[skip ci]` for docs-only pushes, never on the last commit of a push that changes code or CI. Signing changes still need the owner. No co-author lines ([[no-coauthor-attribution]]).
