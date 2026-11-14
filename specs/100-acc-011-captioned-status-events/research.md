# Research: ACC-011 Captioned Status Events

## ACC-011-D1: one router over ACC-004's announcer, not a second announcer

- **Decision**: `StatusEventRouter` owns the existing `AccessibilityAnnouncer`; `AppCoordinator.announcer`
  becomes a computed alias. New kinds keep lanes independent (a recording notice never swallows a source
  change).
- **Rationale**: one gate, one probe, ACC-004's call sites and tests unchanged.
- **Alternatives**: a separate poster per feature (today's state; bypasses the rate rule); one shared kind
  for everything (a burst of source changes would swallow a recording stop).

## ACC-011-D2: one source announcement per change

- **Decision**: both the state and the stop-reason `.onChange` call `announceSourceStatus()`, which
  computes the text from the current manager state: the AUD-014 hold text when it applies, else the
  indicator text. When both fire for one change the second text is identical and the gate drops it.
- **Alternatives**: keep two posts (VoiceOver spoke the status, then status plus explanation).

## ACC-011-D3: blackout announced by phase

- **Decision**: post on `blackoutPhase` changes: blacked out → "Output blacked out"; restore waiting and
  fading in → "Restoring output" (the badge's text; the identical second one is dropped); live →
  "Output restored" with a caption.
- **Rationale**: "Output restored" is now spoken when the output is visible again, not when the restore
  was only requested and is still waiting (OUT-010-R7 spacing). ACC-004's UI test still sees "Output
  blacked out" on Black out.

## ACC-011-D4: captions only where the end state has no text

- **Decision**: `.caption` rows: camera off, OSC off, output restored, last scene reopened. Every other
  row's end state already shows persistent text (indicator, badge, notice, panel, card, sheet).
- **Alternatives**: caption every event (duplicates the visible notice next to it).

## ACC-011-D5: completeness by exhaustive switches plus an enum walk

- **Decision**: catalog switches have no `default:`, so a new enum case does not compile without a row;
  `StatusEventsTests.testEveryStateHasARow` walks every case (`CaseIterable` enums, plus fixed exhaustive
  lists for `StopReason` and `RecordingFailure`, which carry values; `CameraFeedState` gets an app-side
  `allStatusCases` built by an exhaustive switch).
- `scripts/check_status_events.py` keeps direct posts out of the capture and recording files (contract C2).

## ACC-011-D6: background suppression

- **Decision**: the router drops system-caused rows while `AppCoordinator.appIsActive` is false; user rows
  are never dropped (the user acted, so the app is active). AUD-015's notice summarizes on return.

## ACC-011-D7: recording-state rows

- **Decision**: `recording` → "Recording started" (visible "REC m:ss"); `finishing` → "Recording stopped"
  (visible "Finishing…"); `idle` is reached through the offered panel → "Recording ready" (visible panel
  title) or through a notice (stop reason, failure). The state `.onChange` posts on entering `recording`
  and `finishing`; the panel's appearance posts the idle row.
