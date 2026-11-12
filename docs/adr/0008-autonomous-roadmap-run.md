# ADR-0008: Autonomous Roadmap Run

- **Status**: Accepted 2026-11-12 (decided by Claude under the run request's standing approval for
  routine decisions; items marked "owner ruling needed" are not decided here)
- **Date**: 2026-11-12
- **Roadmap**: `docs/FEATURE_ROADMAP_AUTONOMOUS.md` (SHA-256 `77a775e9…a37`) · **Run**: `cb545c51cf0b`
- **Constitution**: I, VI, VII, VIII, X; Privacy; Governance

## Context

The owner asked for every feasible roadmap feature (326 rows) to be specified, implemented,
tested and integrated locally, with physical-device testing last. The roadmap defers to the
constitution and `CLAUDE.md` on conflicts. `docs/autonomous/AUDIT.md` records the preflight, the
dependency graph and the audit of `main` at `029d90c`.

## Decisions

1. **Branches.** `main` is not changed and nothing is pushed (the run request overrides the
   standing push approval in `CLAUDE.md` for this run). All work lands on the local branch
   `autonomous/integration`; each feature is built on `feature/<id>` in its own worktree under
   `.autonomous/worktrees/` and merged with a non-fast-forward merge by one integration writer.
2. **Who executes a feature.** The orchestrator's unattended loop (`orchestrator.py run`) needs a
   logged-in Claude CLI. The CLI on this Mac is not logged in, and logging in is the owner's
   action. Until then the Claude session executes features itself: one agent per feature in that
   feature's worktree, running the six Spec Kit skills in order. The session, not the agent,
   runs the gates, merges and records evidence; an agent's report is never evidence.
3. **Gates.** In a worktree: compliance, docs validation and package tests. The app build and
   app tests run on the integration checkout after the merge, because worktrees have no preset
   submodules. A failed gate is retried at most three times with a new diagnosis, then the
   feature is blocked.
4. **Spec directories and IDs.** One directory per roadmap ID, `specs/NNN-<id>-<slug>`, numbered
   by the scheduler. Requirements, success criteria and tasks are prefixed with the roadmap ID
   (`AUD-001-R1`, `AUD-001-S1`, `AUD-001-T01`) because the three-digit `FR-`/`SC-` space that
   `validate_docs.py` checks cannot hold 326 features.
5. **Analysis boundary (Constitution VIII).** The new spectrum, onset and tempo analysis (ANL
   rows) feeds only the native generators and the modulation graph. projectM keeps receiving
   normalized PCM through its documented API and does its own analysis; nothing computed by the
   new analysis is passed into projectM. The measured need is that projectM exposes no spectrum
   or beat output through its public API for other consumers.
6. **Recording audio (Privacy).** Recording features write audio only on an explicit user
   action, only from In-App Playback of user-owned files or from the microphone with consent,
   and never from System/App Capture. REC-004 gets its own specification and privacy review.
7. **Device evidence.** No feature is device-verified before the final phase. The run reports
   `awaiting_final_device` with prerequisites when a device or controller is missing.

## Owner ruling needed

- **Networking for OSC.** FR-068 and `check_compliance.py` forbid networking APIs in the app.
  OSC-001, 003, 004, 005, 007, 008, 009, 010, 011 and 012 need a UDP listener, a sender or
  Bonjour (directly or through OSC-001). They stay blocked until the owner amends FR-068:
  an exception limited to one source folder, off by default, with a local-network usage
  description. OSC-002 (parser) and OSC-006 (bundle ordering) need no networking.

## Consequences

- The integration branch can be reviewed and merged, or discarded, as a whole; `main` and
  `origin` stay as they were.
- With a blocked OSC group the run cannot reach "strict implementation completion", so the final
  device phase cannot start until the ruling is made (either way: amend, or declare the rows
  infeasible).
