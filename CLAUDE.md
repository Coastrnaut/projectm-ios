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
- Never modify `Vendor/projectM` (pinned submodule). Patches, if ever needed, go in
  `docs/projectm-patches.md`.

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
  - macOS CI minutes cost 10× quota; parallel agents are no reason to push more often.
  - Agents cannot do device tasks or owner decisions, and no agent may start work that the Stage 1
    gate blocks.

## Where things stand (2026-11-08)

- **Stage 1 / Plan Phase A** (capture feasibility) is in progress. Do not start ProjectM engine,
  renderer, or preset work: it is blocked until the Stage 1 gate (task T056) records "go".
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
  Nothing has run on a device yet. The iOS Simulator SDK has no ScreenCaptureKit, so System/App
  Capture can only be tested on D1/D2.
- Owner rulings 2026-11-08 (research doc, "Owner decisions"): `screen-capture` background mode
  decided after T041; the export carries `session.stopDetail`; new StopReason
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
5. Run the device tasks (T040 onward, including the device checks of T113) following
   `specs/001-ios-projectm-visualizer/quickstart.md` (Scenario A rules: start playback first, stay
   in CaptureLab, fill the tester note).

## Commands

```bash
python3 scripts/test_scripts.py          # script tests (any OS)
python3 scripts/validate_docs.py         # spec cross-references
python3 scripts/check_compliance.py      # constitution rules
python3 scripts/verify_environment.py    # toolchain pins (macOS)
swift test --package-path Packages/AudioCore
xcodegen generate && open ProjectM-iOS.xcodeproj
```

CI: `.github/workflows/ios-ci.yml` (docs and compliance → Linux package tests and macOS build/test).
The repo is private, so macOS minutes cost 10× quota (about 4 min per run). Add `[skip ci]` to
docs-only commit messages.

## Conventions

- Commit after each task or skill; no co-author trailers in commit messages.
- Standing owner approval (2026-11-08): push to `origin/main` and let CI run without asking first,
  then check the run's result. Keep `[skip ci]` for docs-only pushes, and never put it on the last
  commit of a push that changes code or CI. Signing changes still need the owner.
- LF line endings everywhere (`.gitattributes`).
