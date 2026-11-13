# Tasks: REC-012 Share via Files

**Input**: design documents in `specs/060-rec-012-share-via-files/` (spec, plan, research,
data-model, contracts/capture-share.md, quickstart).

**Tests**: requested by the spec (REC-012-S1 to S4) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] REC-012-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Setup

- [ ] REC-012-T01 Simulator `REC12 iPhone 17` (iOS 27.2), `xcodegen generate`, preset submodules; PosterBoard reports counted before (no file)

## Phase 2: Foundational (blocks every story)

- [ ] REC-012-T02 [P] `ShareFileStore` per the contract: `defaultDirectory` `<tmp>/Sharing`; `excludedActivityTypes` "[.saveToCameraRoll, .assignToContact]"; `removeLeftovers()` (directory listing only, no file dates); `makeCopy(data:named:)` and `makeCopy(of:named:)` into `<directory>/<UUID>/<named>`; `remove(_:)` deletes the copy's folder; `fileCount()`; `ShareOutcome` (`from(completed:error:)`: error first, then completed, else cancelled; notices "Shared." / none / "The file couldn't be shared."), in `Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift`
- [ ] REC-012-T03 `CaptureShareCoordinator` (main actor, observable): init sweeps leftovers (REC-012-R6); `shareFrame(_:date:)`, `shareRecording(_:)` make the copy and set `request` (one at a time; copy failure → notice, no request, REC-012-R11); `finish(_:)` deletes the copy, clears `request`, sets `lastOutcome` and the notice, never touches the original (REC-012-R4, R5, R15); `simulation` flag from DEBUG `-uitestShareSimulation`; `ActivitySharePresenter` (`UIActivityViewController`, excluded types, completion → `ShareOutcome`, iPad popover anchored to its view), in `Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift`
- [ ] REC-012-T04 `AppCoordinator` owns `captureShare` as a stored property (created at launch, so the sweep runs at launch), in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`

## Phase 3: User Story 1 - Share a frame or a recording (P1)

**Goal**: ready panels with Save…, Share…, Discard; Share… opens the sheet with a named copy.
**Independent test**: unit tests + UI test with the simulation.

- [ ] REC-012-T05 [US1] `FrameCaptureCoordinator`: `offered`, `offeredDate`, `offeredBaseName`; a successful capture (outside the DEBUG folder mode) sets `offered` instead of opening the exporter; `requestExport()`; `exportFinished` success clears `offered`, cancel keeps it; `exportDismissed` keeps it; `discardOffered()`; a new capture replaces `offered`, in `Apps/projectM-iOS/Coordinators/FrameCaptureCoordinator.swift`
- [ ] REC-012-T06 [US1] `VideoRecordingCoordinator`: `offered`; a finished recording (outside the DEBUG folder mode) sets `offered` instead of opening the mover; `requestSave()`; `moverFinished` success clears it, cancel or failure keeps it; `moverCancelled` keeps it; `discardOffered()` deletes the file; Record refuses while offered with "Save, share or discard the last recording first." (probe `refused: resultOffered`, REC-012-R10), in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`
- [ ] REC-012-T07 [US1] `CaptureResultPanels`: "Frame ready" / "Recording ready" panels (identifiers per the contract, accessibility labels, REC-012-R13), the presenter behind each Share…, the share notice, DEBUG simulation buttons and `captureShareProbe`; one line in `VisualizerView.banners`; the exporter's default name from `offeredBaseName`, in `Apps/projectM-iOS/Views/CaptureResultPanels.swift`, `Apps/projectM-iOS/Views/VisualizerView.swift`

## Phase 4: User Story 2 - Cancelling a share keeps the original (P1)

**Goal**: the row's acceptance.
**Independent test**: unit tests on the store and coordinator; UI test cancel path.

- [ ] REC-012-T08 [US2] Unit tests: copy has the original's bytes and descriptive name (frame PNG, recording MP4); cancel → copy and its folder deleted, original kept and unchanged; complete → copy deleted, original kept, "Shared."; failed → copy deleted, notice; copy failure → no request, notice; second request while one is shown is refused; leftovers swept at init; excluded types exactly `[.saveToCameraRoll, .assignToContact]`; outcome mapping (REC-012-S1 to S4), in `Apps/projectM-iOS/Tests/CaptureShareAppTests.swift`
- [ ] REC-012-T09 [US2] UI test with `-uitestShareSimulation` on the seeded Photo visual: Save Frame → PNG → Share… → `copies=1` → simulated cancel → `copies=0 frame=yes`, panel still shown; Record ~1 s → Stop → Share… → simulated completion → `copies=0 recording=yes last=completed`, "Shared."; under 30 s, in `Apps/projectM-iOS/UITests/CaptureShareUITests.swift`

## Phase 5: User Story 3 - Done with the result (P2)

- [ ] REC-012-T10 [US3] Update REC-001 and REC-003 app tests for the offered result (exporter after `requestExport`, cancel keeps, success clears, Discard; mover cancel keeps the file, Discard deletes it, Record refused while offered), in `Apps/projectM-iOS/Tests/FrameCaptureAppTests.swift`, `Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift`

## Phase 6: Polish & cross-cutting

- [ ] REC-012-T11 [P] Privacy review and docs: `docs/privacy-policy.md` (sharing: only on Share…, only to the activity the user picks, temporary copy deleted, Photos and Contacts excluded, results kept only for the session), `docs/release/app-privacy.md` (label unchanged); superseded notes in `specs/055-rec-001-still-frame-capture/spec.md` (REC-001-R10) and `specs/058-rec-003-video-recording/spec.md` (REC-003-R13)
- [ ] REC-012-T12 Gates: `check_compliance.py`, `validate_docs.py`, `check_privacy_manifest.py` on the Debug simulator app; `xcodebuild test` projectM-iOSTests, CaptureShareUITests, FrameCaptureUITests, VideoRecordingUITests on the iOS 27.2 simulator; PosterBoard reports counted after
- [ ] REC-012-T13 {device} D1: AirDrop, Messages and Save to Files from the share sheet for a frame and a recording; cancel keeps the panel; no Photos or Contacts activity, no permission prompt (quickstart, REC-012-S5)

## Dependencies

T01 → T02 → T03 → T04 → US1 (T05-T07) → US2 (T08-T09) → US3 (T10) → T11-T12. T13 last, owner.

## Parallel examples

- T02 with T05 and T06 (separate files); T11 with anything after T07.

## Implementation strategy

MVP = Phases 1-4 (the acceptance). Success criteria: S1, S2 → T08, T09; S3, S4 → T08, T12; S5 → T13.
