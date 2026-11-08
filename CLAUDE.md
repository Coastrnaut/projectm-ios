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

## Where things stand (2026-11-08)

- **Stage 1 / Plan Phase A** (capture feasibility) is in progress. Do not start ProjectM engine,
  renderer, or preset work: it is blocked until the Stage 1 gate (task T056) records "go".
- Verified: 84 Swift package tests pass on Linux (AudioCore 40, CaptureKit 33, Diagnostics 7,
  CaptureUI 4) and 15 Python script tests pass.
- Written but not yet compiled for iOS: `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/SCKStreamDriver.swift`
  (written against the **macOS** ScreenCaptureKit API — iOS symbols unverified), the AVFAudio
  microphone and playback backends, `LifecycleObserver`, the CaptureUI SwiftUI views, the
  CaptureLab app, and `project.yml`.
- Test devices (final; `docs/test-reports/devices.md`): D1 iPhone 15 iOS 27.0.1 (reference),
  D2 iPad Pro M5 iPadOS 27.2, D3 iPad A16 iPadOS 26.5.

## Next tasks on the Mac, in order

1. **T010** — record the Xcode, iOS SDK, Swift, XcodeGen, and CMake versions in
   `docs/adr/0002-minimum-ios-version.md`; `python3 scripts/verify_environment.py` must exit 0.
2. `swift test --package-path Packages/<pkg>` for AudioCore, CaptureKit, Diagnostics, CaptureUI.
3. **T035 (Gate 0)** — from the iOS SDK headers, write
   `docs/platform-research/screencapturekit-ios.md` (RI-001/RI-004), fix `SCKStreamDriver`, and
   replace the placeholder `@available(iOS 27.0, *)` with the verified first version.
4. `xcodegen generate`, then build and run CaptureLab on the devices (set the signing team by hand).
5. Record each device's OS build and model identifier in devices.md, then run the device tasks
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

CI: `.github/workflows/ios-ci.yml` (docs and compliance, Linux package tests, macOS build).

## Conventions

- Commit after each task or skill; no co-author trailers in commit messages.
- LF line endings everywhere (`.gitattributes`).
