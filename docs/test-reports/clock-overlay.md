# MED-011 Clock Overlay — test report (2026-11-14)

Spec: `specs/262-med-011-clock-overlay/`. Simulator results are never device evidence (Constitution X).

## Design (decided under owner rules 4 and 9; spec Clarifications)

- The clock is a MED-009 `TextLayerSource` (name "clock") attached as a `.clock` layer on top of each compositor
  visual's stack (Photo, Video, Camera, Text), after MED-010's logo: content, so it reaches captures, recordings and
  the external display. projectM and the native spectra have no compositor and show no clock (Settings says so).
- Time from an injected `ClockSource` (app: `Date()` and `TimeZone.current`; no network time). `DateFormatter` with
  fixed patterns `HH:mm`, `HH:mm:ss`, `h:mm a`, `h:mm:ss a` and an injected locale and time zone.
- A main-actor task ticks at each whole second while the clock is shown and a layer is live; a new spec is pushed
  only when the string changes, so the layer rasterizes once per change and CMP-013 reuses its picture in between.
- Off by default; settings in `settings.clock.overlay` (versioned JSON), backed up, erased with Settings, removed
  by the UI-test reset. No elapsed-show-time mode and no scene field in this row.

## Results (Mac Studio, Xcode 27.2, simulator "MED11 iPhone 17" iOS 27.2)

| Check | Result |
|---|---|
| `swift test --package-path Packages/Compositor --filter Clock` (host) | 8/8: ClockFormatterTests 6 (S1 exact strings, S4 midnight and New York DST, change detection, schedule, settings JSON), ClockLayerTests 2 (S2 identical pixels and +1 minute different; S3 60 ticks → 1 rasterization, 1 render) |
| Full Compositor package (host) | 1073 tests, 0 failures, 51 s |
| Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, filter `Clock|TextSpec`) | pass (ClockFormatterTests 6) |
| LibraryBackup package | 87 tests, 0 failures |
| App unit tests (simulator) | ClockOverlayStoreTests 3, SettingsTests 9, LibraryBackupAppTests 5, LibraryEraseAppTests 3, TextOverlayStoreTests 5, LogoStoreTests 6: 31/31 |
| UI tests (simulator) | ClockOverlayUITests 1/1 (10.0 s; "14:05" drawn on the Text visual after Show Clock), LogoOverlayUITests 1/1 (28.8 s, unchanged with the clock layer above the logo) |
| Repo checks | compliance, docs, motion policy, permission catalog, status events OK; script tests 179 OK (1 skipped) |
| Debug app | `check_privacy_manifest` OK; `check_network_symbols` OK |
| Type-check budget | no new warning in the feature's files (the remaining warnings are pre-existing) |
| PosterBoard reports | 28 before, 28 after |

## Open

- MED-011-T13 `{device}`: D1 and D3 readability, minute change against the status bar, seconds mode, a recording with
  the clock.
