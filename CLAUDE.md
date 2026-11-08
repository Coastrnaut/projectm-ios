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

- **Parallelize as much as possible.** Target at least 50 agents running at once, with a maximum of
  150. One workflow runs at most about 16 agents at a time, so this means four or more workflows
  running concurrently (background subagents count too). Token usage is not a constraint.
- **Fan out every substantive task:** parallel researchers or finders, each result checked by
  several skeptics told to refute it; one auditor per document for consistency sweeps; parallel
  review angles on every diff; agents that prepare ready-to-apply patches for pending owner
  decisions. Start independent workflows at the same time, not one after another.
- **Limits that still apply:**
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
- CI is green (GitHub Actions): macOS-host and iOS-Simulator package tests; all packages and
  CaptureLab build for generic iOS with Xcode 26.6 / iOS SDK 26.5. That SDK has **no**
  ScreenCaptureKit, so the capture driver is compiled out on CI (see
  `docs/platform-research/screencapturekit-ios.md`).
- Compiled on CI but never run on a device: the AVFAudio backends, `LifecycleObserver`, the
  CaptureUI views, and the CaptureLab app.
- Never compiled yet (needs the iOS 27 SDK): `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/SCKStreamDriver.swift`
  (written against the **macOS** ScreenCaptureKit API — iOS symbols unverified).
- Project Mac = build machine of record (2026-11-08): Xcode 27.2 / iOS SDK 27.2 / Swift 6.4.2,
  XcodeGen 2.46.0, CMake 4.4.5, pinned in ADR-0002 (T010; `verify_environment.py` exits 0).
  Simulator runtimes iOS 27.2 and iOS 26.5. Locally: 86 package tests pass on the macOS host
  (AudioCore 42, incl. 2 Apple-only), 15 script tests pass, `xcodegen generate` works.
- CI's runner has only Xcode 26.x, so it cannot match the pin; the iOS 27 path is built and tested
  only on the project Mac until GitHub ships Xcode 27 (ADR-0002).
- Test devices (final, recorded by T017 in `docs/test-reports/devices.md`; all paired, Developer
  Mode on): D1 iPhone 15 `iPhone15,4` iOS 27.0.1 (reference), D2 iPad Pro M5 `iPad17,3`
  iPadOS 27.2, D3 iPad A16 `iPad15,7` iPadOS 26.5.

## Next tasks on the Mac, in order

1. Done 2026-11-08: T010 (toolchain pin), package tests on macOS, T017 (devices).
2. Before each work session: `python3 scripts/verify_environment.py` must exit 0.
3. **T035 (Gate 0)** — from the iOS SDK headers, write
   `docs/platform-research/screencapturekit-ios.md` (RI-001/RI-004), fix `SCKStreamDriver`, and
   replace the placeholder `@available(iOS 27.0, *)` with the verified first version.
4. `xcodegen generate`, then build and run CaptureLab on the devices (set the signing team by hand).
5. Re-check devices.md if any device OS changed (T017 done), then run the device tasks
   (T040 onward) following `specs/001-ios-projectm-visualizer/quickstart.md`.

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
