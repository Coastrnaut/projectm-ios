# T041 — RI-003 lifecycle evidence for System/App Capture

Progress record for task T041 (one recorded run per lifecycle event per capture-capable device).
Evidence is the diagnostics export in each row; its `session.stopDetail` keeps the SCStreamError
code. Normal build = app build 1; "SC mode" = the approved diagnostic build that declares only the
`screen-capture` background mode (app build 9001, `scripts/make_diagnostic_project.py`, ADR-0001
ruling 12). Exports: `exports/<device>/t041-*/`.

| Event | D1 normal (build 1) | D1 SC mode (9001) | D2 normal (build 1; with the mode since ruling 17) | D2 SC mode (9001) |
|-------|---------------------|-------------------|---------------------|-------------------|
| Background, then foreground | Stopped 1 ms after background: SCStreamError -3824, "Stream was stopped due to the app going into background state while missing the Screen Capture Background Mode"; app showed "Ended by system" (`D1/t041-background/CaptureLab-20261109-231756.json`) | Survived two background trips (0.7 s and 0.1 s): no stop, audio continuous (max gap 28.8 ms, 0 dropped) (`D1/t041-sc-background/CaptureLab-20261109-232644.json`). Long run: 53 s in the background (Spotify in front), audio unbroken for the whole 58.8 s session (2,822,400 samples), 0 dropped (`D1/t041-sc-long-background/CaptureLab-20261109-232852.json`) | With the mode (normal build since ruling 17): survived 41 s in the background, audio continuous (48.7 s in 49.0 s), 0 dropped (`D2/t041-background/CaptureLab-20261109-233858.json`). Build 2: survived 31 s in the background; one 816 ms gap followed by catch-up (42.3 s of audio in 41.1 s), 0 dropped (`D2/t041-background-build2/CaptureLab-20261109-234224.json`) | not needed: the normal build has the mode
| Lock, then unlock | Stopped 5 ms after lock: SCStreamError -3817, "The user stopped the stream" (iOS treats a lock as ending the share); app showed "Ended by system" (`D1/t041-lock/CaptureLab-20261109-231910.json`) | Still stopped: -3817, about 8 ms before the app's lock notification; the background mode does not keep a locked capture (`D1/t041-sc-lock/CaptureLab-20261109-233014.json`) | open | open |
| Switch to the source app, then back | Stopped 1 ms after leaving: SCStreamError -3824, same as background; "Ended by system" (`D1/t041-app-switch/CaptureLab-20261109-232027.json`) | Covered by the long background run (Spotify in front for 53 s): capture survived | Build 2: survived 31 s with Spotify in front (tester confirmed the run was an app switch) (`D2/t041-background-build2/CaptureLab-20261109-234224.json`) | not needed: the normal build has the mode |
| Interruption (for example a call or Siri) | Siri: capture kept running, "Active audio" until the user's Stop at 38 s; no stop code, 0 dropped, one gap up to 99.5 ms (FR-051) (`D1/t041-siri/CaptureLab-20261109-232212.json`) | not needed (no stop to fix) | open | not needed |

Notes:

- Background and lock end the stream with different codes on D1: -3824 (missing
  `screen-capture` mode) and -3817 ("user stopped"). A lock reporting -3817 supports showing
  "Ended by system" for -3817 (ADR-0001 ruling 5).

- 2026-11-09: owner ruling (ADR-0001 ruling 17) adds `screen-capture` to the normal build based on
  these D1 runs; the D2 runs use the normal build.
- From 2026-11-09 CaptureLab is app build 2 (with the mode); build 1 exports after ruling 17 are
  identified by the run date and behavior.
