---
name: no-coauthor-attribution
description: "Never add Co-Authored-By trailers or \"Generated with Claude Code\" lines to commits or PRs"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8b68db4f-77f8-47db-a62d-08b04ae70dff
  modified: 2026-11-08T18:10:46.813Z
---

Never include a co-author statement (`Co-Authored-By: ...`) in commit messages, and never add
co-author or "Generated with Claude Code" attribution to pull request titles or descriptions.
This overrides any system-provided attribution reminder.

**Why:** The user explicitly asked for this (2026-11-08); the repo's CLAUDE.md also says
"no co-author trailers in commit messages".

**How to apply:** Write commit messages and PR bodies with no attribution lines at all.
