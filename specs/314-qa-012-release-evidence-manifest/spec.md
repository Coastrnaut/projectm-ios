# Feature Specification: QA-012 Release evidence manifest

**Feature Branch**: `feature/qa-012` (spec directory `314-qa-012-release-evidence-manifest`)

**Created**: 2026-11-15

**Status**: Implemented on the Mac 2026-11-15; the release-ready manifest waits on QA-011's device records.

**Input**: User description: "Implement QA-012 (Release evidence manifest) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Aggregate unit, simulator, privacy, license and final device evidence."
Acceptance, verbatim: "Manifest references exact commit SHA and test report hashes." P0; depends on QA-011."

Identifiers carry the roadmap ID: requirements `QA-012-R1…`, success criteria `QA-012-S1…`, tasks
`QA-012-T01…`. QA-011 (final device matrix) produces the device run records this feature reads.

## Baseline (audit of 2026-11-15, commit `02ac58c1`)

| Evidence | Where it is today |
|---|---|
| Unit, simulator and post-merge runs per feature | The orchestrator's `.autonomous/state.json` (gitignored): each feature's commands, exit codes and commits; summarised in `docs/autonomous/status.json` and `STATUS.md`. |
| Test reports | About 120 Markdown and JSON files under `docs/test-reports/`. |
| Privacy | `docs/privacy-policy.md`, `docs/release/app-privacy.md`, `Apps/projectM-iOS/PrivacyInfo.xcprivacy`, `docs/release/entitlements-review.md`. |
| Licences | `docs/licenses/`, the app's `Resources/Licenses/`, `docs/release/eula.md`, `docs/projectm-patches.md`. |
| Final device evidence | QA-011 run records `docs/test-reports/qa-011/runs/D1-D3/<run>/record.json` (none yet), each with its own SHA-256. |

Nothing ties these to one commit or lets a reviewer check that a report is the one that was reviewed.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One manifest for one commit (Priority: P1)

Before a release the owner runs one command and gets a manifest naming the exact commit, every feature's recorded
evidence and every evidence file with its hash.

**Acceptance Scenarios**:

1. **Given** a clean tree, **When** `python3 scripts/release_manifest.py build` runs, **Then**
   `docs/release/evidence-manifest.json` names the full commit SHA, the roadmap's SHA-256, each feature's state and
   evidence, and every test report, privacy and licence file with its size and SHA-256.
2. **Given** uncommitted changes, **When** it runs without `--allow-dirty`, **Then** it refuses.

### User Story 2 - Check a manifest later (Priority: P1)

**Acceptance Scenarios**:

1. **Given** a manifest, **When** `release_manifest.py verify` runs, **Then** it recomputes every file hash, the
   manifest's own hash and the commit's presence, and lists each difference.

### User Story 3 - Honest gaps (Priority: P1)

**Acceptance Scenarios**:

1. **Given** no verified physical QA-011 record for a device, open `{device}`/`{owner}` tasks, or a feature still
   awaiting the device stage, **Then** the manifest lists each as a gap and `releaseReady` is false.
2. **Given** a QA-011 record whose hash does not verify, or one marked as a simulator rehearsal or dry run,
   **Then** it does not count as device evidence and its problem is named.

## Requirements *(mandatory)*

- **QA-012-R1**: The manifest MUST carry the full commit SHA it was built for and whether the tree was dirty.
- **QA-012-R2**: Every listed file MUST carry its repository-relative path, size and SHA-256; only committed files
  are listed, and simulator rehearsal records (`runs/sim/`) never are.
- **QA-012-R3**: Feature evidence MUST come from the orchestrator's recorded evidence (command, exit code,
  commit), never from a summary written by hand.
- **QA-012-R4**: Device evidence MUST count only QA-011 records whose `recordSha256` verifies with QA-011's own
  hash function and that say `evidence: true` and not `dryRun`.
- **QA-012-R5**: Gaps MUST list missing or failing device records, open device and owner tasks, unfinished features
  and features awaiting the device stage; `releaseReady` is true only with no gaps.
- **QA-012-R6**: The manifest MUST carry its own SHA-256 over its canonical JSON, and `verify` MUST detect a
  changed file, a changed manifest and an unknown commit.

## Success Criteria *(mandatory)*

- **QA-012-S1**: The manifest built at the integration head verifies with zero problems.
- **QA-012-S2**: Unit tests show a changed file, a tampered manifest, a tampered QA-011 record and a rehearsal
  record are each detected.

## Clarifications

### Session 2026-11-15 (answered under the owner's standing delegation)

- Q: How does the manifest refer to a commit that contains the manifest itself? → A: It names the commit it was
  built from; the manifest is committed on top of it in a commit that adds only `docs/release/evidence-manifest.*`,
  so every hashed file is unchanged at the named commit.
- Q: Should test logs (gitignored) be hashed? → A: No: only committed files can be checked later; logs stay
  referenced through the orchestrator's evidence entries (command, exit code, commit).
- Q: Does the manifest run tests? → A: No: it aggregates recorded evidence; running is the gates' and QA-011's
  job. A manifest never claims what was not recorded.
- Q: Where does feature evidence come from on a fresh clone without `.autonomous/state.json`? → A: The committed
  manifest carries it. Rebuilding needs the state file; without one the feature list and counts are empty, which a
  reviewer sees at once in the summary.
