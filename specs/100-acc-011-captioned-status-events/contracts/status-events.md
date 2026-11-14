# Contract: Captioned Status Events (ACC-011)

## C1 — Transition table

Cause: U = user-caused, S = system-caused. Presentation: P = persistent text already on screen, C = transient
status caption (4 s), SP = system-presented (iOS UI, no app announcement). Announced rows follow ACC-011-R4:
user-caused, safety-relevant, or required by the cited earlier requirement. `<status>` is the source
indicator text, `UIStrings.sourceStatus` (FR-042), e.g. "In-App Playback · Active audio".

| ID | Transition | Visible text | Announcement | Kind | Cause | Pres. | Why announced |
|---|---|---|---|---|---|---|---|
| X1 | source → any AudioState (notStarted, waiting, noAudioReceived, silent, active, paused, interrupted, stopped, endedBySystem) | `<status>`; banner with the FR-015 message where one applies | `<status>` | source | S | P | FR-070; interrupted, stopped, ended by system and no audio are safety-relevant |
| X2 | source switch waiting for the new source (AUD-012) | "Switching source…" | "Switching source…" | source | U | P | user-caused |
| X3 | In-App Playback on hold (interrupted, output disconnected; AUD-014) | `<status>` + hold detail | "`<status>`. `<detail>`" (replaces X1's text for that change) | source | S | P | AUD-014-R18, safety |
| X4 | background notice on return (AUD-015) | notice text | notice text | background | S | P | AUD-015-R7 |
| X5 | output route changed (AUD-007) | route explanation | `UIStrings.routeAnnouncement` | route | S | P | AUD-007 |
| X6 | Save Frame refused, failed or "Frame saved." (REC-001) | notice | notice | capture | U | P | user-caused (new) |
| X7 | frame offered (REC-012) | "Frame ready" | "Frame ready" | capture | U | P | user-caused (new) |
| X8 | share finished or failed (REC-012) | share notice | share notice | capture | U | P | user-caused (new) |
| X9 | recording idle → recording (REC-003) | "REC m:ss" | "Recording started" | recording | U | P | user-caused (ACC-004) |
| X10 | recording → finishing | "Finishing…" | "Recording stopped" | recording | U/S | P | ACC-004; automatic stops are safety |
| X11 | finishing → idle with the file offered | "Recording ready" | "Recording ready" | recording | U | P | user-caused (new) |
| X12 | recording refused (each `RecordingRefusal`, incl. REC-015 low storage) | refusal notice | refusal notice | recording | U | P | user-caused |
| X13 | recording stopped automatically (each `RecordingStopReason` except `user`: limit, background, paused, blacked out, visual changed, size changed, presentation lost, writer failed, low storage) | stop notice | stop notice | recording | S | P | safety (data) |
| X14 | recording failed (each `RecordingFailure`) | failure notice | failure notice | recording | S | P | safety (data) |
| X14a | recording moved to Files ("Recording saved.") | "Recording saved." | same | recording | U | P | user-caused |
| X15 | camera → requestingAccess | iOS permission alert | — | camera | U | SP | iOS reads its own alert |
| X16 | camera → starting / running (CAM-012, CAM-002) | "Camera on" / "Front camera on" | same | camera | U | P | user-caused (new); privacy |
| X17 | camera → denied, restricted (FILE-013), unavailable, interrupted, failed (CAM-001/002) | permission/camera notice | same | camera | S | P | safety (permission, privacy) |
| X18 | camera → idle (user's Stop camera) | "Camera off" | "Camera off" | camera | U | C | user-caused |
| X19 | OSC listener opened (OSC-007) | "OSC listening on port N" | same | osc | S | P | privacy (network listener) (new) |
| X20 | OSC stopped from the badge | "OSC off" | "OSC off" | osc | U | C | OSC-007-R7 |
| X21 | output → blacked out (OUT-010/SHOW-014) | "Output blacked out" | same | output | U | P | ACC-004 |
| X22 | output → restore waiting / fading in | "Restoring output" | same | output | U | P | user-caused |
| X23 | output → live after a blackout | "Output restored" | same | output | U | C | ACC-004 |
| X24 | recovery offer shown (PERF-010) | card title and message | "`<title>` `<message>`" (once per launch) | session | S | P | PERF-010-R4 |
| X25 | last scene reopened (PERF-010) | "Last scene reopened." | same | session | U | C | user-caused |
| X26 | repair report shown (SCN-012) | sheet | "`<title>`: `<status>`." | session | U | P | SCN-012 |
| X27 | external display connection settled (OUT-002) | "External display connected" (while a recording holds the visual: "External display connected. It shows the visualization when the recording ends.") | same | display | S | C | OUT-002-R6 |
| X28 | a settled external display disconnected (OUT-002) | "External display disconnected" | same | display | S | C | OUT-002-R6 |

Not announced (ACC-011-R4): automatic preset changes (ACC-004-R6), the recording's elapsed-time ticks,
camera starting → running (the same row X16; dropped as identical), the second blackout restoring phase
(identical text), transient OSC listener closes, and every system row while the app is not active.

## C2 — Files checked for direct posts

`scripts/check_status_events.py` fails when any of these files contains `UIAccessibility.post` or
`AccessibilityNotification`:

- `Apps/projectM-iOS/Coordinators/StatusEvents.swift`
- `Apps/projectM-iOS/Coordinators/AppCoordinator+StatusEvents.swift`
- `Apps/projectM-iOS/Coordinators/FrameCaptureCoordinator.swift`
- `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`
- `Apps/projectM-iOS/Coordinators/CaptureShareCoordinator.swift`
- `Apps/projectM-iOS/Coordinators/RouteCoordinator.swift`
- `Apps/projectM-iOS/Coordinators/SceneRepairCoordinator.swift`
- `Apps/projectM-iOS/Views/VisualizerView.swift`
- `Apps/projectM-iOS/Views/SourceStatusIndicator.swift`
- `Apps/projectM-iOS/Views/BackgroundNoticeView.swift`
- `Apps/projectM-iOS/Views/OSCListenerBadge.swift`
- `Apps/projectM-iOS/Views/SessionRecoveryOfferCard.swift`
- `Apps/projectM-iOS/Views/CameraIndicator.swift`
- `Apps/projectM-iOS/Views/CaptureResultPanels.swift`
- `Apps/projectM-iOS/Views/StatusCaptionView.swift`

and `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` except lines naming one of the out-of-scope
announcements: `onScopeChange` (FR-124), `nativeVisualUnavailableMessage` (VIS-001), `glowUnavailableMessage`
(FX-001).

## C3 — Test probes (DEBUG)

- `announcementProbe` (ACC-004, `-uitestDiagnostics`): "<kind>|<text>" of the last spoken announcement.
- `statusCaption`: the caption view itself (static text, label = the caption) while a caption shows.
