# Contract: performance report export (PERF-012)

- **C1 File**: `projectM-performance-<UTC yyyyMMdd-HHmmss>.json`, UTF-8 JSON, pretty-printed, sorted keys, valid
  against `performance-report.schema.json` (schema version 1, `kind` `projectM-iOS.performanceReport`).
- **C2 Settings**: Settings → Performance, a button "Export performance report" (identifier
  `performanceReport.export`) after the overlay toggle; footer: what the file holds and that frame times are measured
  while the performance overlay is shown. A failed write shows "The file couldn't be shared." (identifier
  `performanceReport.notice`), no sheet.
- **C3 Share**: the system share sheet with one temporary copy in `<tmp>/Sharing/<UUID>/`; every outcome deletes it
  (REC-012). DEBUG `-uitestShareSimulation`: the buttons `simulateShareCompleted` / `simulateShareCancelled` replace
  the sheet; "Shared." appears after completed.
- **C4 Privacy**: every string value in the file is a schema enum member, a `const`, `exportedAt`, or system metadata
  (model, OS version and build, app version and build). Nothing is sent anywhere; no preference is stored.
- **C5 Signpost**: one Points of Interest event "Performance report" per export with counts only (samples, timeline
  entries).
