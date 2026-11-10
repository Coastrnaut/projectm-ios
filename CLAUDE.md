# ProjectM-iOS — agent guide

iPhone/iPad audio visualizer built on the ProjectM engine. Work follows GitHub Spec Kit:
the governing documents are `.specify/memory/constitution.md` and
`specs/001-ios-projectm-visualizer/` (spec, plan, research, data-model, contracts, quickstart,
tasks). `README.md` is background guidance; the constitution and spec win when they differ.

## Rules that are easy to break

- **Public Apple APIs only.** No private APIs, `dlsym`/`dlopen`, ReplayKit, or capture workarounds.
  `python3 scripts/check_compliance.py` enforces this and runs in CI on every push.
- **No compatibility claims without evidence.** A source "works" only with a CaptureLab diagnostics
  export from a physical device showing non-silent audio (FR-031). Simulator results and
  screenshots are never evidence. Never write that Spotify, Apple Music, etc. work.
- **Signing is manual.** Never commit or change signing teams, certificates, or profiles.
- **Keep the iPad A16 (D3) on iPadOS 26.5.** It is the only device covering the iOS 26 path.
- **Report honestly.** If a build or test could not run on this host, say so ("pending macOS",
  "pending device"). Mark a task `[X]` in tasks.md only when its acceptance criterion was verified,
  and say how.
- `Vendor/projectM` is pinned to the owner's fork (`Coastrnaut/projectm`, branch `ios`; Constitution
  VIII v1.1.0). Engine changes are made on that branch only as upstream-ready commits, each logged
  in `docs/projectm-patches.md` and meant for an upstream PR; then the pin moves (ADR-0004).
- `Vendor/angle` is the owner's fork of ANGLE (`Coastrnaut/angle`, branch `ios`, shallow; ADR-0004).
  `gclient sync` puts about 12 GB of dependencies inside it (gitignored). Never delete or move it;
  scripts write only to `Build/ANGLEFrameworks` (macOS volumes are case-insensitive).

## Working with agents (owner preference, 2026-11-08)

- **No multi-agent requirement.** Use agents only when they clearly help, and run **at most 10
  agents at once** in total (all workflows and background subagents together).
- **Limits:**
  - One writer per repo file. Agents write to scratch files, copies, or worktrees; the main session
    applies their output (especially tasks.md, spec.md, project.yml, and the contracts).
  - An agent's report is not evidence. Verify it (build, test, read the diff) before marking a task
    `[X]`.
  - Builds and simulator runs share one Mac: agents read, review, and type-check; only a few lanes
    build or run tests.
  - CI minutes on GitHub's standard runners are free since the repo went public (2026-11-09); still
    push finished work, not every step.
  - Agents cannot do device tasks or owner decisions, and no agent may start work that the Stage 1
    gate blocks.

## Where things stand (2026-11-08)

- **Stage 1 is complete: T056 recorded "go" on 2026-11-09** (`docs/test-reports/compatibility-report.md`,
  Stage Decision). No source is claimed to work (none rated; Gates 1-2 waived).
- **Plan Phase B is complete; the owner accepted the Plan B exit on 2026-11-09.** T057-T061
  (Normalizer, normalized ring, `CaptureManager.normalizedOutput`), T062 (signposts; points
  accepted for delivery and residency, residency trace moved to T114), T063 on D1 (no allocations
  or lock-wait syscalls in any audio callback; CPU 7.4%, 3-minute run by owner ruling). Next is
  Plan Phase C (engine build and render proof, T064-T079 plus T114).
- **Plan Phase C is complete and Gate 3 passed on 2026-11-09** (T079): ADR-0003 accepts Option B,
  the engine on ANGLE's Metal backend (`Packages/ANGLERendering`, `Vendor/angle` = the owner's
  ANGLE fork). Engine: `Vendor/projectM` at the owner's fork commit `c88894e` (four iOS patches,
  `docs/projectm-patches.md`). Device evidence from RendererLab sweeps on D1-D3
  (`docs/test-reports/performance.md`, `docs/test-reports/exports/rendererlab/`); owner rulings: no
  10-minute sessions, no quality tiers or flash-limiter measurement for Gate 3. Next: Phase D (US4,
  T080 onward); T114 done with ProjectMiOS.
- Phase D started 2026-11-09: `ProjectMiOS` (project.yml) runs notice → chooser → full-screen ANGLE
  visualizer with controls; T080, T082, T083, T085, T086, US5 T088-T091, US6 T094-T096 and US7 T098-T100 done (T081, T093: red run not recorded); T081 (red run not recorded) and T084
  (FR-089 on D1/D2) open; T087 needs the devices and a 240 fps camera. The app's signing team is set
  by hand in Xcode (or in the gitignored `Configs/Signing.local.xcconfig`). 2026-11-10: T101 done
  (SC-009 on D1 and D3), SC-007 and SC-015 measured; T102 not required, Gate 4 waived (owner
  ruling). Phase E (2026-11-10): T103, T104 (Reduce flashing on D1: median 1.21 ms, max 1.55 ms),
  T106, T107, T108 (privacy review on D1, zero violations), T109 (ADR-0005 final "go", owner
  approved), T110, T111 done; T105 code done, its SC-012 audit not required (owner ruling); T112 done: 1.0 (1) archived, open device rows waived, upload by the owner (`docs/test-reports/release-report.md`). Build the binaries first:
  `python3 scripts/build_projectm_xcframework.py` and `python3 scripts/build_angle_xcframework.py`.
- Phase B verified on the project Mac 2026-11-09: AudioCore 76, CaptureKit 80, Diagnostics 8 tests
  on the host and the iOS 27.2 and 26.5 simulators; CaptureLab UI tests (3) on iOS 27.2; device
  builds with no warnings. The Linux path (no AVFAudio: linear resampler fallback) is tested on
  the Mac with `swift test -Xswiftc -DAUDIOCORE_NO_AVFAUDIO`.
- Verified: 84 Swift package tests pass on Linux (AudioCore 40, CaptureKit 33, Diagnostics 7,
  CaptureUI 4) and 15 Python script tests pass.
- CI is green (run 42552713447, 2026-11-09). The main job runs on `macos-26` with the image's
  newest Xcode 26 (iOS SDK 26.5, no ScreenCaptureKit): package tests on the macOS host and an iOS 26
  simulator, generic-iOS builds with the capture driver compiled out. `build-ios27` runs on GitHub's
  `xcode-27` preview image with Xcode 27.2 (27B52; it warns on any other build): it compiles the
  driver and CaptureLab for devices and runs the package tests on an iOS 27.2 simulator (about
  4.5 min). CI does not run the CaptureLab UI tests.
- Project Mac = build machine of record: Xcode 27.2 / iOS SDK 27.2 / Swift 6.4.2, XcodeGen 2.46.0,
  CMake 4.4.5 (ADR-0002, T010). Simulators iOS 27.2 and 26.5 (23F77 only). Verified here
  2026-11-08 (after the owner review): package tests (AudioCore 50, CaptureKit 74, Diagnostics 8,
  CaptureUI 10) on the host and both simulators; CaptureLab UI tests (3) on both simulators; 54
  script tests; device builds of everything, including `SCKStreamDriver`, with no compiler
  warnings; Debug and Release device builds load ScreenCaptureKit as `LC_LOAD_WEAK_DYLIB`.
- Gate 0 met: research done (T035, `docs/platform-research/screencapturekit-ios.md`), and the
  owner accepted ADR-0001 and ADR-0002 on 2026-11-08 (owner review). The Screen Recording
  entitlement that Apple's iOS sample declares was added (ADR-0001 Decision 6), then removed on
  2026-11-09: it is offered only to organization accounts (ruling 16). CaptureLab declares no
  entitlement; T040 shows whether capture works without it (-3803 would mean it does not).
  The review's rulings and their status are in each ADR's "Owner review" section.
  First device run (2026-11-09): on D1, System/App Capture without the entitlement received
  non-silent Spotify audio (20.8 s), and so did D2 (22.4 s; first audio after 1.5 s, one ~1 s gap);
  exports in `docs/test-reports/exports/`. D3 (iPadOS 26.5): the Debug build launches (weak link
  works), System/App Capture shows "Requires a newer iOS version", In-App Playback is non-silent.
  Not rated yet (FR-031 needs 10 min). T040 complete 2026-11-09 (`docs/test-reports/t040-us1.md`). The iOS Simulator SDK has no
  ScreenCaptureKit, so System/App Capture can only be tested on D1/D2.
- Owner rulings 2026-11-08 (research doc, "Owner decisions"): `screen-capture` background mode
  added on 2026-11-09 after T041 on D1 (ADR-0001 ruling 17; a lock still ends capture, -3817); the export carries `session.stopDetail`; new StopReason
  `screenRecordingNotAllowed` for -3801 and `isAvailable` false; RI-003 is checked at Gate 2, not
  Gate 0; a compile-only CI job runs on the `xcode-27` image.
- Test devices (final, recorded by T017 in `docs/test-reports/devices.md`; all paired, Developer
  Mode on): D1 iPhone 15 `iPhone15,4` iOS 27.0.1 (reference), D2 iPad Pro M5 `iPad17,3`
  iPadOS 27.2, D3 iPad A16 `iPad15,7` iPadOS 26.5.

## Next tasks on the Mac, in order

1. Done 2026-11-08: T010, T017, T033 (previews checked in Xcode's canvas), T035 (Gate 0 research),
   T037, the Mac-verifiable Phase A tasks, and the owner-review rulings that need no device (see
   the ADRs' "Owner review" sections).
2. Before each work session: `python3 scripts/verify_environment.py` must exit 0 (it also checks
   the Xcode build, 27B52).
3. Before any TestFlight upload, follow `docs/release/capturelab-distribution.md` (Release
   `otool` check, D3 launch).
4. `xcodegen generate`, set the signing team by hand, and run CaptureLab on D1, D2 and D3. If the
   first System/App Capture start fails with -3803, the entitlement is needed: enroll as an
   organization or ask Apple (`docs/platform-research/apple-question-screen-recording-entitlement.md`),
   then restore ADR-0001 Decision 6.
5. Close Stage 1: T054 (thresholds), T055 (LGPL preliminary conclusion), then the owner's T056
   go/no-go. T049-T053 and T113 are not required and Gates 1-2 are waived (ADR-0001 rulings 18,
   19); no source is claimed to work. Device procedures:
   `specs/001-ios-projectm-visualizer/quickstart.md` (Scenario A rules: start playback first, stay
   in CaptureLab, fill the tester note).

## Commands

```bash
python3 scripts/test_scripts.py          # script tests (any OS)
python3 scripts/validate_docs.py         # spec cross-references
python3 scripts/check_compliance.py      # constitution rules
python3 scripts/verify_environment.py    # toolchain pins (macOS)
python3 scripts/check_capturelab_export.py --json <export> --expect none   # check a device export
python3 scripts/make_diagnostic_project.py no-usage-key   # temporary diagnostic build (9002)
swift test --package-path Packages/AudioCore
xcodegen generate && open ProjectM-iOS.xcodeproj
```

CI: `.github/workflows/ios-ci.yml` (docs and compliance → Linux package tests and macOS build/test).
The repo is public since 2026-11-09 (owner decision), so standard GitHub-hosted runners are free.
Add `[skip ci]` to docs-only commit messages. Commits use the owner's normal git email (owner
decision 2026-11-09: no noreply address).

## Conventions

- Commit after each task or skill; no co-author trailers in commit messages.
- Standing owner approval (2026-11-08): push to `origin/main` and let CI run without asking first,
  then check the run's result. Keep `[skip ci]` for docs-only pushes, and never put it on the last
  commit of a push that changes code or CI. Signing changes still need the owner.
- LF line endings everywhere (`.gitattributes`).
