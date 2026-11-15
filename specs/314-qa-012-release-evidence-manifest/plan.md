# Implementation Plan: QA-012 Release evidence manifest

**Spec**: [spec.md](spec.md) · **Branch**: `feature/qa-012`

## Summary

One Python script, `scripts/release_manifest.py`, with `build` and `verify`. `build` reads the orchestrator's state
for feature evidence, globs the committed evidence groups (test reports, performance, privacy, licences, the
autonomous run's documents), reads QA-011 device records through QA-011's own `record_hash`, reads QA-011's
inventory for open device tasks, derives the gaps and writes `docs/release/evidence-manifest.json` plus a Markdown
summary. `verify` recomputes everything.

## Technical context

Python 3 standard library only (as every script in `scripts/`); `git ls-files` decides what is committed and
`git rev-parse HEAD` names the commit. Tests in `scripts/test_scripts.py` (`ReleaseManifestTests`) build manifests
on temporary trees without git (`use_git=False`).

## Constitution check

No app code, no networking, no device action. Evidence rules (Constitution X): simulator rehearsals are excluded
and only verified physical QA-011 records count as device evidence.

## Files

- `scripts/release_manifest.py` (new)
- `scripts/test_scripts.py` (`ReleaseManifestTests`)
- `docs/release/evidence-manifest.json`, `docs/release/evidence-manifest.md` (generated after integration)
- `docs/test-reports/release-evidence-manifest.md` (test report)
