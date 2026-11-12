---
name: commit-push-cadence
description: Commit after every task, skill and complete fileset change, and push right after; never batch finished work
metadata:
  type: feedback
---

Commit after every task, after every Spec Kit skill, and after every complete change to a set of
files (a fix plus its tests, a doc update). Push right after each commit or small group of
commits, once it builds and its tests pass; don't hold work back for CI or long test runs.

**Why:** The owner said (2026-11-10) "remember to commit more frequently, after each task, and
skill and complete fileset change. also push more often". Long sessions had piled several tasks
into single commits and waited on test runs before pushing.

**How to apply:** After finishing each piece, run its tests, then `git commit` and
`git push origin main` before starting the next piece. This works with the standing push approval
([[push-ci-standing-approval]]) and the rule against co-author lines ([[no-coauthor-attribution]]).
Also recorded in CLAUDE.md under Conventions.
