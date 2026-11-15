# Tasks: QA-012 Release evidence manifest

**Input**: [spec.md](spec.md), [plan.md](plan.md)

Format: `- [ ] QA-012-Tnn Description (file)`. Budgets (owner rule 7): each unit test ≤ 10 s.

## Phase 1: Manifest

- [X] QA-012-T01 `build`: commit SHA and dirty check, roadmap hash, feature evidence from the orchestrator state,
  evidence groups of committed files with sizes and SHA-256 (simulator rehearsals excluded), manifest hash
  (`scripts/release_manifest.py`) — Verified 2026-11-15: ReleaseManifestTests; a trial build at `02ac58c1` hashed
  160 files and `verify` reported OK
- [X] QA-012-T02 Device evidence through QA-011's `record_hash`; only physical, non-dry-run, verifying records count
  (`scripts/release_manifest.py`) — Verified 2026-11-15: `test_only_verified_physical_device_records_count`
- [X] QA-012-T03 Gaps and `releaseReady` (missing or failing device records, open device and owner tasks,
  unfinished and awaiting features) — Verified 2026-11-15: `test_gaps_keep_the_release_open_until_everything_is_recorded`,
  `test_open_device_tasks_from_the_inventory_are_a_gap`
- [X] QA-012-T04 `verify`: file hashes, manifest hash, commit presence — Verified 2026-11-15:
  `test_verify_reports_a_changed_file_and_a_tampered_manifest`
- [X] QA-012-T05 Markdown summary — Verified 2026-11-15: trial build wrote `evidence-manifest.md`
- [X] QA-012-T06 Repo checks: `test_scripts.py` (210 OK), `check_compliance.py`, `validate_docs.py` — Verified
  2026-11-15

## Phase 2: After integration

- [X] QA-012-T07 Build the manifest at the integration head (after QA-012 merges), commit
  `docs/release/evidence-manifest.*` alone, push; `verify` must report OK (QA-012-S1) — Verified 2026-11-15: built for commit a59818dd, 161 files, verify OK; release ready no (5 gaps: D1-D3 records, 247 open device tasks, QA-011 awaiting)
- [ ] QA-012-T08 {device} Rebuild the manifest after QA-011-T19 to T22 commit the D1-D3 records; release ready only
  when it lists no gaps
