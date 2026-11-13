# Contract: Scene repair report (SCN-012)

## R1 Building a report

- `SceneRepairReport(refusal: SceneDecodeError)`: one entry. `newerVersion` and `invalidVersion` →
  group unsupportedVersion; every other refusal → damagedFile. Severity cannotOpen, no actions.
  `newerVersion` reads "Made by a newer version of the app: update the app to open it."
- `SceneRepairReport(document:decodeWarnings:registry:assets:)`: one entry per decode warning and per
  `validate` issue (MOD-013 issues included), mapped by code (data-model table). Errors with an
  owning action → needsRepair; errors without → cannotOpen; user-relevant warnings (missingAsset,
  mapping codes, unknownLayerKind) → problem; other warnings → note.
- `SceneRepairReport.open(bytes:registry:assets:) -> SceneRepairOpening`: decode, then report;
  `document` is nil for a refusal. Never throws, never traps.

## R2 Repairing

- `SceneDocument.repairing(_ actions: [SceneRepairAction], registry:, assets:) -> SceneDocument`.
  Pure; runs the given actions in canonical order whatever order they are listed in; each re-validates.
- Idempotent: `d.repairing(a).repairing(a) == d.repairing(a)`.
- With `report.repairActions`, the result has no error issues whenever `report.canOpenWithRepairs`.
- Touches only items of the action's codes; the scene ID, unknown layers, unknown fields and
  unknown parameter values are kept.

## R3 App

- Show step: absent file → SHOW-001 notice (unchanged). Decode refusal → request with the refusal
  report (Close only). Report `needsReview` → request; output unchanged until Open. Otherwise apply as
  today.
- Open with repairs → `repairing(report.repairActions)` → `liveState` → apply; the stored file is not
  written. Open as is → only when `canOpenAsIs`. Cancel → nothing applied.
- Reopen (PERF-010): held scene report `needsReview` → request before `markReopened`; Cancel keeps the
  offer pending.
- Archive import result: `repairReport` built from the imported document and its warnings.
- Launch restore: unchanged.

## R4 Accessibility identifiers

Sheet `sceneRepairReport`; group headers `sceneRepairGroup.<group>`; buttons
`sceneRepairOpenRepaired`, `sceneRepairOpenAsIs`, `sceneRepairCancel`; status text
`sceneRepairStatus` ("Cannot open", "Needs repair", "Opens with problems").
