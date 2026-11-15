# MED-012 Countdown Overlay — test report (2026-11-14)

Spec: `specs/265-med-012-countdown-overlay/`. Simulator results are never device evidence (Constitution X).

## Design (decided under owner rules 4 and 9; spec Clarifications)

- A pure `CountdownTimer` on an injected `MonotonicClock` (app: Swift's `ContinuousClock`, never wall time):
  `remaining(at:) = max(0, duration − elapsed)`, duration 1 s to 99 min, Start/Pause/Reset. `advance(at:)` returns
  true exactly once per run, on the update that reaches zero, then holds at zero. Reset and a Start after the
  finish re-arm it.
- Face: remaining whole seconds rounded up, "mm:ss" below an hour, "h:mm:ss" from it; "00:00" only at zero and held.
- At zero: hold, no flashing; "Countdown finished" announced once on a new `.countdown` `AccessibilityAnnouncer` lane.
- Drawn like MED-011's clock and sharing its plumbing: `ChangedText` (change-only strings; `ClockText` now uses
  it), `StoredOverlayDecodeResult`/`StoredOverlayCodec` (versioned stored value; the clock's result is an alias),
  `OverlayTextLayers` and `Compositor.attachOverlay(_:kind:)` (the clock's attach goes through it). The `.countdown`
  layer sits above `.clock` on the Photo, Video, Camera and Text visuals, so it is content.
- Trigger by hand in Settings › Countdown, or by a show cue: scenes carry an optional top-level `countdown`
  (`{"durationSeconds": N}`); "Start From New Cues" records it in new cue scenes; applying such a scene through a cue
  restarts the countdown with N. Launch restore and reopen never start it. A cue never changes the saved settings.
- Off by default; `settings.countdown.overlay` (versioned JSON), backed up, erased with Settings, removed by the
  UI-test reset. The running state is not stored.

## Results (Mac Studio, Xcode 27.2, simulator "MED12 iPhone 17" iOS 27.2)

| Check | Result |
|---|---|
| TextLayerTests (host), all 8 classes | 44 passed, 0 failures (~6 s): CountdownTimerTests 8 (S1 exact strings at 0, 0.5, 1, 60, 299, 299.5, 300 s and "1:39:00"; S2 one finished event over skipped updates and a 10-hour overrun, one large jump, repeats; pause/resume; Reset re-arms; clamps; schedule; settings JSON), CountdownLayerTests 1 (S3: a 3 s run over 6 s gives "00:03", "00:02", "00:01", "00:00", 4 rasterizations and renders, nothing after zero), the clock's tests unchanged |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, filter `Countdown|Clock`) | pass (26 tests) |
| SceneFormat package (host) | 203 tests, 0 failures (SceneCountdownTests 2: round trip byte-identical, no warning; malformed values absent and kept verbatim) |
| LibraryBackup package | 87 tests, 0 failures |
| App unit tests (simulator) | CountdownOverlayTests 3, ClockOverlayStoreTests 3, SettingsTests 9, LibraryBackupAppTests 5, ShowCoordinatorTests 8, LibraryEraseAppTests 3, LogoStoreTests 6, TextOverlayStoreTests 5: 42/42 |
| UI tests (simulator) | CountdownOverlayUITests 1/1 (13.0 s: Show Countdown + Start → "05:00 running" drawn on the Text visual), ClockOverlayUITests 1/1 (16.0 s), LogoOverlayUITests 1/1 (11.5 s) |
| Repo checks | compliance, docs, motion policy, permission catalog, status events OK; script tests 179 OK (1 skipped) |
| Debug app | `check_privacy_manifest` OK; `check_network_symbols` OK |
| Type-check budget | no warning in the feature's files (the remaining warnings are pre-existing) |
| PosterBoard reports | 30 before, 30 after |

## Open

- MED-012-T14 `{device}`: on D1, a 0:10 countdown reaches "00:00" once and holds, VoiceOver says "Countdown finished"
  once, and a recording contains the countdown.
