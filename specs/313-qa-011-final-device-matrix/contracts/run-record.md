# Contract: QA-011 device run record

File: `docs/test-reports/qa-011/runs/<D1|D2|D3|sim>/<run-id>/record.json`, with `record.md` (readable summary)
and `record.json.sha256` (`<hex>  record.json`). `run-id` = UTC `YYYYMMDDTHHMMSSZ`.

```json
{
  "kind": "projectM-iOS.qa011.deviceRun",
  "schemaVersion": 1,
  "runId": "20261115T120000Z",
  "label": "D1",
  "evidence": true,
  "evidenceNote": "physical device run" | "simulator rehearsal, not evidence",
  "dryRun": false,
  "target": {"kind": "device" | "simulator", "identifier": "...", "udid": "...", "name": "...",
             "productType": "iPhone15,4", "osVersion": "27.0.1", "osBuild": "24A446", "state": "connected"},
  "app": {"bundleID": "org.projectmios.ProjectMiOS", "version": "1.1", "build": "2", "path": "...",
          "configuration": "Release+PROJECTM_AUTOMATION", "commit": "<40 hex>", "dirty": false},
  "signing": {"signed": true, "identity": "Apple Development: …", "team": "XXXXXXXXXX", "adhoc": false,
              "raw": ["Authority=…", "TeamIdentifier=…"]},
  "host": {"xcode": "Xcode 27.2 Build version 27B52", "macOS": "27.2"},
  "startedAt": "…Z", "finishedAt": "…Z",
  "cases": [{"id": "autorun-perf001", "kind": "autorun", "status": "pass", "durationSeconds": 61.2,
             "closes": ["PERF-001-T16"], "commands": [["xcrun", "devicectl", "…"]],
             "detail": "…", "artifacts": [{"path": "…", "bytes": 1234, "sha256": "…", "kind": "file" | "folder",
             "committed": true}]}],
  "summary": {"pass": 0, "fail": 0, "timeout": 0, "blocked": 0, "error": 0, "skipped": 0, "not-run": 0},
  "stopReason": null | "locked" | "unavailable",
  "recordSha256": "<hex of canonical JSON without this field>"
}
```

Rules: keys sorted, two-space indent, LF. Artifact paths are relative to the repository root. `evidence` is false
for a simulator target and for a dry run (a dry run writes nothing). A consumer verifies a record by recomputing
`recordSha256` and each artifact hash (`run_device_matrix.py verify <record.json>`).
