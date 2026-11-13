# Contract: capture sharing (REC-012)

## `ShareFileStore` (app, value type)

```swift
struct ShareFileStore {
    let directory: URL                                   // default <tmp>/Sharing
    static var defaultDirectory: URL
    static let excludedActivityTypes: [UIActivity.ActivityType]   // [.saveToCameraRoll, .assignToContact]
    func removeLeftovers()                               // deletes every item in `directory` (listing only)
    func makeCopy(data: Data, named: String) throws -> URL      // <directory>/<UUID>/<named>
    func makeCopy(of file: URL, named: String) throws -> URL    // FileManager.copyItem
    func remove(_ copy: URL)                             // deletes the copy's folder
    func fileCount() -> Int                              // files under `directory` (probe, tests)
}
```

## `ShareOutcome`

`static func from(completed: Bool, error: (any Error)?) -> ShareOutcome` — error first, then
completed, else cancelled. `notice`: "Shared." / nil / "The file couldn't be shared.".

## `CaptureShareCoordinator` (main actor, observable)

| Member | Contract |
|---|---|
| `init(store:simulation:)` | calls `store.removeLeftovers()` (REC-012-R6) |
| `request` | the sheet shown, nil when none |
| `notice`, `clearNotice()` | REC-012-R15 |
| `lastOutcome` | last `ShareOutcome` (probe, tests) |
| `shareFrame(_ frame: CapturedFrame, date: Date)` | copy with `CapturedFrameDocument.defaultFilename`; on failure notice, no request (R11) |
| `shareRecording(_ url: URL)` | copy named `url.lastPathComponent` |
| `finish(_ outcome: ShareOutcome)` | deletes the copy, clears `request`, sets the notice; never touches the original (R4, R5) |

Refuses a second request while one is shown (the sheet is modal; returns without copying).

## Coordinators

- `FrameCaptureCoordinator`: `offered`, `offeredDate`, `offeredBaseName`, `requestExport()` (document +
  exporter), `exportFinished(_:)` (success clears `offered`; cancel keeps it), `exportDismissed()`
  (keeps it), `discardOffered()`.
- `VideoRecordingCoordinator`: `offered`, `requestSave()` (mover with `offered`), `moverFinished(_:)`
  (success clears; cancel or failure keeps), `moverCancelled()` (keeps), `discardOffered()` (deletes the
  file); `toggle()` while `offered != nil` refuses with "Save, share or discard the last recording
  first." (probe `refused: resultOffered`).

## UI identifiers

| Identifier | Element |
|---|---|
| `frameResult`, `frameResultSave`, `frameResultShare`, `frameResultDiscard` | "Frame ready" panel |
| `recordingResult`, `recordingResultSave`, `recordingResultShare`, `recordingResultDiscard` | "Recording ready" panel |
| `captureShareNotice`, `captureShareNoticeText`, `captureShareNoticeDismiss` | share notice |
| `captureShareProbe` (DEBUG) | `copies=<n> frame=<yes\|no> recording=<yes\|no> last=<completed\|cancelled\|failed\|none>` |
| `simulateShareCompleted`, `simulateShareCancelled` (DEBUG) | simulation buttons |
