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
- CI is green (GitHub Actions) on `macos-latest` (Xcode 26.6 / iOS SDK 26.5, no ScreenCaptureKit):
  package tests on the macOS host and iOS 26 simulator, generic-iOS builds with the capture driver
  compiled out. The `build-ios27` job uses the newest Xcode 27 on GitHub's `xcode-27` preview image
  to compile the driver and CaptureLab for iOS devices (ADR-0002); first green run 42529663444 used
  Xcode 27.2 (27B52, the pinned build) and confirmed the driver's symbols. CI does not run the
  CaptureLab UI tests.
- Project Mac = build machine of record: Xcode 27.2 / iOS SDK 27.2 / Swift 6.4.2, XcodeGen 2.46.0,
  CMake 4.4.5 (ADR-0002, T010). Simulators iOS 27.2 and 26.5. Verified here 2026-11-08 (after the
  owner rulings): package tests (AudioCore 50, CaptureKit 65, Diagnostics 8, CaptureUI 10) on the
  host and both simulators;
  CaptureLab UI tests (3) on both simulators; 28 script tests; device builds of everything,
  including `SCKStreamDriver`, with 0 warnings.
- Gate 0 research done (T035): `docs/platform-research/screencapturekit-ios.md`. ADR-0001 and
  ADR-0002 accepted by T035, pending owner review. Nothing has run on a device yet. The iOS
  Simulator SDK has no ScreenCaptureKit, so System/App Capture can only be tested on D1/D2.
- Owner rulings 2026-11-08 (research doc, "Owner decisions"): `screen-capture` background mode
  decided after T041; the export carries `session.stopDetail`; new StopReason
  `screenRecordingNotAllowed` for -3801 and `isAvailable` false; RI-003 is checked at Gate 2, not
  Gate 0; a compile-only CI job runs on the `xcode-27` image.
- Test devices (final, recorded by T017 in `docs/test-reports/devices.md`; all paired, Developer
  Mode on): D1 iPhone 15 `iPhone15,4` iOS 27.0.1 (reference), D2 iPad Pro M5 `iPad17,3`
  iPadOS 27.2, D3 iPad A16 `iPad15,7` iPadOS 26.5.

## Next tasks on the Mac, in order

1. Done 2026-11-08: T010, T017, T035 (Gate 0 research), T037 and the Mac-verifiable Phase A tasks.
2. Before each work session: `python3 scripts/verify_environment.py` must exit 0.
3. Owner: open `Previews.swift` in Xcode's canvas to close T033; review the ADR-0001/0002 acceptances.
4. `xcodegen generate`, then build and run CaptureLab on D1, D2 and D3 (set the signing team by hand).
5. Run the device tasks (T040 onward) following `specs/001-ios-projectm-visualizer/quickstart.md`
   (Scenario A rules: start playback first, stay in CaptureLab, fill the tester note).

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
- LF line endings everywhere (`.gitattributes`).
