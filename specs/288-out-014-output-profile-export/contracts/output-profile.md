# Contract: OUT-014 Output Profile

## C1 — PresentationLifecycle `OutputProfile.swift`
- `OutputProfile` (Equatable, Sendable) with the fields of data-model.md; `OutputProfile.Calibration`.
- `OutputDisplayClass(readings: OutputReadings, screenPixelAspect: Double?) -> OutputDisplayClass?` (nil without a native size);
  `match(_ connected: OutputDisplayClass?) -> OutputDisplayClassMatch`; `summary` ("1920 × 1080 px, pixel aspect 1.00, 60 Hz, sRGB").
- `OutputProfileDocument.encode(_:) -> Data`; `decode(_ data: Data) throws(OutputProfileImportError) -> OutputProfile`;
  `fileName`, `fileExtension` (`pmoutput`), `maxBytes` (16384), `format`, `version` (1).
- `OutputProfileImportError`: `empty`, `tooLarge`, `notAProfile`, `newerVersion(Int)`, `missingField(String)`,
  `unknownField(String)`, `invalidValue(String)`; `message` per case. Nothing is returned on any error.

## C2 — App
- `ExternalOutputSetting.outputProfile(display:)` and `apply(_ profile:)` (every property set inside the call; the
  existing didSets persist and push to `ExternalDisplayCoordinator`).
- `ExternalOutputSetting.profiles: OutputProfileCoordinator`.
- `ExternalDisplayCoordinator.outputDisplayClass: OutputDisplayClass?` (OUT-011 readings + the slot's screen pixel aspect).
- `OutputProfileCoordinator`: `prepareExport(_ setting:)`, `exportFinished`, `exportCancelled`, `importFile(at:into:)`,
  `importData(_:into:)`, `pending` (+ `pendingText`), `applyPending(into:)`, `cancelPending()`, `message`, `lastExport`
  (DEBUG simulation and tests), `simulation`.

## C3 — Settings › External Display
- Buttons "Export output profile…" (`outputProfileExport`) and "Import output profile…" (`outputProfileImport`),
  status text `outputProfileMessage`, confirmation dialog with "Apply Anyway" (`outputProfileApplyAnyway`) and Cancel.
- DEBUG `-uitestOutputProfileSimulation`: no mover or picker; export keeps the document; import reads it.
