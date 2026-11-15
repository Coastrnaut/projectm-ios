---
name: remove-worktrees-after-merge
description: "Owner rule: remove each feature worktree (and its agent simulators) as soon as the feature is merged into the integration branch"
metadata:
  type: feedback
---

Remove a feature's worktree as soon as it is integrated (owner, 2026-11-14). That day the disk showed 660 GB used: `.autonomous/worktrees` held 263 checkouts (207 GB), 241 of them already merged, because nothing called `Worktrees.remove`.

**Why:** leftover worktrees and agent-created simulators (93 GB) filled the Mac Studio's disk.

**How to apply:** after a merge passes the integration gates, run `Worktrees.remove(<id>)` (`git worktree remove`, never `--force`). Keep the branch, and keep any worktree with uncommitted work but report it. Before each batch, remove any leftover merged worktree no running agent uses, then `git worktree prune`. Delete simulators that agents created for finished features. Keep at most the concurrency limit of feature worktrees on disk. Related: [[never-stop]], [[short-tests]].
