# QA-012 release evidence manifest: test report

Spec: [specs/314-qa-012-release-evidence-manifest/](../../specs/314-qa-012-release-evidence-manifest/spec.md).

## What it does

`python3 scripts/release_manifest.py build` writes `docs/release/evidence-manifest.json` and `.md` for the current
commit; `python3 scripts/release_manifest.py verify` recomputes every hash. The manifest lists:

- the full commit SHA, whether the tree was dirty, and the roadmap's SHA-256;
- every roadmap feature's state with its recorded evidence (command, exit code, commit) from the orchestrator;
- every committed test report, performance threshold file, privacy document and licence file with its size and
  SHA-256 (simulator rehearsals under `runs/sim/` are excluded);
- the QA-011 device records for D1-D3, counted only when their own hash verifies and they are physical runs;
- the gaps that keep the release open, and `releaseReady`.

## Tests (2026-11-15)

`ReleaseManifestTests` in `scripts/test_scripts.py`, 5 tests, 0.01 s:

- files are hashed, simulator rehearsals excluded, and the manifest verifies;
- `verify` reports a changed file and a tampered manifest;
- only verified physical device records count (a rehearsal written as a device run and a tampered record are
  both refused, with the reason);
- gaps keep the release open until all three devices are recorded and no feature waits on the device stage; a
  record with a failing case is a gap;
- open `{device}`/`{owner}` tasks from QA-011's inventory are a gap.

Full script suite: 210 tests, OK (1 skipped). `check_compliance.py` and `validate_docs.py`: OK.

Trial build at commit `02ac58c1` (scratch output, not committed): 160 files (120 test reports, 2 performance, 4
privacy, 30 licence, 4 run documents), 323 integrated features, gaps: no device record for D1, D2 or D3, 263 open
device and owner tasks, QA-011 awaiting the device stage, and QA-012 itself still implementing. `verify`: OK.

## Not verified

- A release-ready manifest: it needs QA-011's device records (QA-011-T19 to T22, owner present).
