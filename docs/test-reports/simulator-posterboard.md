# Simulator PosterBoard crashes (2026-11-13)

The owner saw many "PosterBoard quit unexpectedly" dialogs on the Mac Studio and asked for them to
be monitored and fixed as required (CLAUDE.md owner rule 5). This file logs each investigation.
Simulator crashes are not evidence about the app either way.

## What PosterBoard is

PosterBoard is the iOS lock-screen and wallpaper ("poster") process. In a simulator it runs under
`launchd_sim`; when it crashes, macOS writes `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips`
and may show a "quit unexpectedly" dialog on the Mac.

## Findings, 2026-11-13 (32 reports, 2026-11-11 18:01 to 2026-11-13 06:16)

- Every report is a `SIGTRAP` (`EXC_BREAKPOINT`, an assertion inside Apple's code) in PosterBoard's
  own startup:
  - 28 at `-[PRPosterDescriptor _initWithPath:]`, under
    `-[PBFAmbientRoleCoordinator finalizeChangesWithChangeHandler:…]` during
    `-[PBFPosterExtensionDataStore _stateLock_initialRoleCoordinatorSetup]`;
  - 4 at `pf_posterPathInstanceURLForVersionsURL:` while configuring the file system for a new
    poster.
  No frame involves projectM-iOS. The runtime is iOS 27.2 (24B8117); no iOS 26.5 report was found.
- The reports cluster in bursts: 20:00-22:00 on 2026-11-12, when three agents were booting
  simulators for test runs, and 06:04-06:16 on 2026-11-13, when the simulators resumed after the
  Mac slept and one was erased and rebooted.
- A simulator that stays booted settles: after the bursts, `launchd_sim` logged no PosterBoard
  exits on any booted simulator, and no report has been written since 06:16.

## What was tried

| Step | Result |
|---|---|
| Erased the iOS 27.2 "iPhone 17" simulator (`4E32B01D`), the integration test simulator, and rebooted it | 3 more reports at 06:16:40-43, during that boot; none afterwards. Stored data was not the cause. |
| Booted an idle iOS 27.2 "iPhone Air" and an idle iOS 26.5 "iPhone 17", 150 s each | 0 reports for either. A plain boot does not always trigger it. |

## Conclusion and handling

This is a fault in the iOS 27.2 simulator's PosterBoard while it sets up its poster data store
(the stack passes through `initWithURL:…wasMigrated:`), not in the app and not fixable in this
repository. It shows up in bursts when simulators are booted, erased or resumed. Handling:

1. Keep one long-lived booted simulator per job (the integration checkout uses `4E32B01D`; each
   feature agent gets its own fixed simulator) instead of booting fresh ones, and do not erase a
   simulator unless its state is shown to be wrong.
2. After each simulator run, count new reports; if a burst continues on a simulator that is
   already booted, record it here and try that simulator on the other iOS 27.2 runtime build or a
   fresh device of the same type.
3. Do not turn off macOS crash reporting globally (it would hide real crashes); that needs the
   owner.

## 2026-11-14 afternoon (autonomous run)

Four new reports (14:52, 15:14, 15:17 twice; total 26 → 28 counted with the two 15:17 files), all
`EXC_BREAKPOINT` in PosterBoard under `launchd_sim`, each while a feature agent booted a fresh
per-feature simulator (VIS-008, CAM-003, UIX-007 iPad). Same signature as above; no burst on a
long-lived simulator, so no simulator was erased. No action beyond this note.
