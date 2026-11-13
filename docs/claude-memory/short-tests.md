---
name: short-tests
description: No more 30-minute test runs; tests must be short and concise and exist to produce evidence
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-13T14:09:48.968Z
---

Keep every test and every test run short: a test exists to produce evidence, not to sweep every combination.

**Why:** On 2026-11-13 the owner said "dont run any more 30 minute tests, tests should be short and concise to generate evidence, remember this and commit it to claude". At that point post-merge checks bundled many UI suites (15-30 minutes per feature), the AnalysisFeatures acceptance tests swept every FFT size × hop × rate × backend (15-67 s each, about 4.5 minutes per suite run), and two PresetCollections UI tests took 110-120 s each.

**How to apply:**
- Budgets (host, Debug): a unit or package test about 1-2 s, at most 10 s; a whole package suite under 1 minute; a UI test under 30 s; any one check (worktree gate or post-merge check) under 10 minutes. Report a test that exceeds its budget and shorten it.
- Acceptance tests use a few representative cases that cover each rule (the edges plus one typical case per dimension), not the full cross-product. A full sweep, if wanted, lives in a bench or a script run on demand, never in the default test run or CI.
- Post-merge checks run only the tests that cover what the merge changed: the touched packages' suites and the feature's own UI tests plus at most one neighbouring UI suite, not every UI suite.
- Agent briefs carry these budgets.
