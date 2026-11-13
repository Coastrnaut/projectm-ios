# ADR-0008: Autonomous Roadmap Run

- **Status**: Accepted 2026-11-12 (decided by Claude under the run request's standing approval for
  routine decisions); OSC networking ruled by the owner 2026-11-12
- **Date**: 2026-11-12
- **Roadmap**: `docs/FEATURE_ROADMAP_AUTONOMOUS.md` (SHA-256 `77a775e9…a37`) · **Run**: `cb545c51cf0b`
- **Constitution**: I, VI, VII, VIII, X; Privacy; Governance

## Context

The owner asked for every feasible roadmap feature (326 rows) to be specified, implemented,
tested and integrated locally, with physical-device testing last. The roadmap defers to the
constitution and `CLAUDE.md` on conflicts. `docs/autonomous/AUDIT.md` records the preflight, the
dependency graph and the audit of `main` at `029d90c`.

## Decisions

1. **Branches.** Features are built on `feature/<id>` in their own worktrees under
   `.autonomous/worktrees/` and merged into `autonomous/integration` with a non-fast-forward merge
   by one integration writer. Owner ruling 2026-11-12 ("remember to automatically push to main"):
   once a merged feature passes its post-merge gates, `origin/main` is fast-forwarded to
   `autonomous/integration` and CI is checked; nothing is ever force-pushed. (Until that ruling
   the run request's "do not push" applied and `main` was untouched.)
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

## Owner ruling: networking for OSC (2026-11-12)

The owner ruled: "amend FR-068 for OSC, one-folder exception, off by default".

- FR-068 in `specs/001-ios-projectm-visualizer/spec.md` carries the amendment.
- `scripts/check_compliance.py` allows the Network framework only under
  `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/`; `URLSession`,
  CFNetwork, sockets and WebKit stay forbidden everywhere, including that folder. Script tests
  cover the folder boundary.
- OSC-001, 003, 004, 005, 007 to 012 are no longer blocked by policy. They must keep the
  listener and sender off until the user enables them (OSC-007), use the local network only,
  and add the local-network usage description (and the Bonjour service list for OSC-011) to the
  app's Info.plist through `project.yml`. The privacy policy and the App Store privacy answers
  are updated in the feature that first ships a listener.

## Owner ruling: feature policy choices (2026-11-12)

The owner ruled "all recommended for policy choices". The choices the feature agents made and
reported as recommended stand, and each is recorded in its spec's Clarifications:

- AUD-002: sample rates limited to 8 kHz to 192 kHz; the new import messages stand.
- AUD-006: the end of a track advances to the next imported track (repeat modes are AUD-004).
- PRE-012: imported copies of built-in presets are refused; an incomplete shader is quarantined.
- AUD-014: no automatic resume after an interruption that ends in the background; the
  deprecated iOS interruption notification stays until device task T29 shows otherwise.

## Decision for PRE-014 (export), taken under the owner's best-judgement rule (2026-11-12)

PRE-015 asked whether user copies of locked-pack presets may be exported. Decision: PRE-014
exports a copy of a bundled preset only when its source is an Included preset; copies whose
source is in a pack that the purchase unlocks are left out of every export, edited or not, and
the export summary lists how many were left out and why. Exported copies keep `duplicateOf`,
`rightsVerified = false` and the pack's statement. Reason: the purchase sells access to the
bundled packs (ADR-0007), and an export must never become a way to hand that content on.

## Consequences

- Each integrated feature reaches `origin/main` after its post-merge gates, so CI runs on it.
