---
name: best-judgement-on-choices
description: "Owner delegated all product and policy choices to Claude's best judgement (2026-11-12); decide, record, and report instead of asking"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4b2d0feb-fd64-48f8-b2a5-67452c70c822
  modified: 2026-11-13T00:07:23.099Z
---

Decide product, design and policy choices yourself with best judgement; do not ask the owner to confirm them.

**Why:** On 2026-11-12, during the autonomous roadmap run, the owner first ruled "all recommended for policy choices" and then said "use your best judgement on all choices moving forward, remember this and write it to claude". Also recorded in CLAUDE.md (owner rules) and ADR-0008.

**How to apply:**
- Pick the conservative, local-first option that fits the constitution, record it where it belongs (the spec's Clarifications, an ADR when it overrides a default), and mention it in the report as decided, not as a question.
- Still the owner's alone, unchanged: signing teams, certificates and profiles; App Store Connect, agreements, banking, purchases and releases; anything on a physical device that needs a person; amendments to Constitution principles I and V; destructive or irreversible git actions.
- In the autonomous run, pushing stays off ([[push-ci-standing-approval]] is suspended for that run by the run request); no co-author lines ([[no-coauthor-attribution]]).
