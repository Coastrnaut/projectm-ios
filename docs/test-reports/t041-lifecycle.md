# T041 — RI-003 lifecycle evidence for System/App Capture

Progress record for task T041 (one recorded run per lifecycle event per capture-capable device).
Evidence is the diagnostics export in each row; its `session.stopDetail` keeps the SCStreamError
code. Normal build = app build 1; "SC mode" = the approved diagnostic build that declares only the
`screen-capture` background mode (app build 9001, `scripts/make_diagnostic_project.py`, ADR-0001
ruling 12). Exports: `exports/<device>/t041-*/`.

| Event | D1 normal (build 1) | D1 SC mode (9001) | D2 normal (build 1) | D2 SC mode (9001) |
|-------|---------------------|-------------------|---------------------|-------------------|
| Background, then foreground | Stopped 1 ms after background: SCStreamError -3824, "Stream was stopped due to the app going into background state while missing the Screen Capture Background Mode"; app showed "Ended by system" (`D1/t041-background/CaptureLab-20261109-231756.json`) | open | open | open |
| Lock, then unlock | Stopped 5 ms after lock: SCStreamError -3817, "The user stopped the stream" (iOS treats a lock as ending the share); app showed "Ended by system" (`D1/t041-lock/CaptureLab-20261109-231910.json`) | open | open | open |
| Switch to the source app, then back | Stopped 1 ms after leaving: SCStreamError -3824, same as background; "Ended by system" (`D1/t041-app-switch/CaptureLab-20261109-232027.json`) | open | open | open |
| Interruption (for example a call or Siri) | open | open | open | open |

Notes:

- Background and lock end the stream with different codes on D1: -3824 (missing
  `screen-capture` mode) and -3817 ("user stopped"). A lock reporting -3817 supports showing
  "Ended by system" for -3817 (ADR-0001 ruling 5).
