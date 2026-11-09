# ADR-0002: Minimum iOS Version and Toolchain

- **Status**: Accepted by the project owner (owner review 2026-11-08): deployment target (owner
  clarification 2026-11-07); toolchain pin (T010); first OS with System/App Capture =
  iOS/iPadOS 27.0 (Gate 0, T035, RI-004). The review's rulings, and what is still to implement,
  are listed under "Owner review (2026-11-08)".
- **Date**: 2026-11-07 (accepted 2026-11-08; owner review 2026-11-08)
- **Spec**: Clarifications 2026-11-07, FR-008, FR-032 · **Research**: R-01

## Context

The stakeholder clarified that the app must run on iOS/iPadOS 26+, on any iOS 26-capable device,
with System/App Capture only where the OS provides it.

## Decision

- **Deployment target**: iOS 26.0 and iPadOS 26.0, one app for the iPhone and iPad device family.
- **SDK**: the iOS 27 SDK (or newer), needed to compile the System/App Capture adapter. Only the
  device SDK has ScreenCaptureKit; the iOS 27.2 Simulator SDK does not, so the adapter is compiled
  for devices only and System/App Capture is unavailable on every simulator.
- **Feature gating**: System/App Capture is availability-gated to iOS 27.0, the version in every
  ScreenCaptureKit annotation of the iOS 27.2 SDK (ADR-0001; RI-004). The Debug device build
  weak-links ScreenCaptureKit (deployment target 26.0; checked with `otool -L` on
  CaptureLab.debug.dylib; no Release build has been checked), so it should load on iOS 26, where
  the framework is absent; confirmed only when CaptureLab runs on D3. Owner review 2026-11-08:
  device builds get an explicit `-weak_framework ScreenCaptureKit`, and before any TestFlight
  upload a Release build is checked with `otool` and launched on D3 (not implemented yet). All
  other features are meant to work on iOS 26; Microphone and In-App Playback are checked on D3 in
  T049.
- **Toolchain pin** (recorded 2026-11-08, task T010): Xcode `27.2` (build 27B52), SDK `27.2`
  (iOS, SDK build 24B8118), Swift `6.4.2`, XcodeGen `2.46.0`, CMake `4.4.5`.
  `scripts/verify_environment.py` reads these values and must exit 0 on the build Mac. It compares
  the version numbers only, not the Xcode build; the owner review (2026-11-08) adds a check for
  27B52 (not implemented yet).

- **Build machine of record**: the project Mac (macOS 27.2, Apple silicon), which has Python 3.15
  (scripts need 3.10+) and simulator runtimes for iOS 27.2 and iOS 26.5 (23F77, the same build
  as D3). A second iOS 26.5 runtime, 23F73, has the same identifier; the owner review orders it
  removed (not done yet). Every `{mac}` build or test result is reported against this pin.
- **CI**: the main job runs on GitHub's `macos-latest` image (`macos-26-arm64`, image
  20261102.0473.1): Xcode 26.0–26.6, the iOS 26.5 SDK and iOS 26.x simulator runtimes. It covers the
  iOS 26 path, installs the pinned XcodeGen, and runs `verify_environment.py` as a warning, because
  the Xcode/SDK/Swift pin cannot match there. GitHub also offers an `xcode-27` image (`runs-on:
  xcode-27`, a public preview announced 2026-07-16 in actions/runner-images#14404; image
  20261026.0314.1 has Xcode 27.2 as release candidate 27B48, not the pinned 27B52, and the iOS
  27.0–27.2 SDKs). Owner ruling 2026-11-08: the CI job `build-ios27` runs there on every run and
  compiles CaptureKit (including the System/App Capture driver) and CaptureLab for iOS devices, at
  the cost of extra macOS minutes (10× quota on this private repository). Because the image's
  Xcode 27 builds change, the job uses the newest Xcode 27 that can build for iOS devices; that
  selection is an implementation choice, not part of the ruling. The job only compiles; the iOS 27
  path is tested on the build Mac and on devices. First green run: 42529663444 (2026-11-08) on
  image 20261104.0337.1, which ships Xcode 27.2 build 27B52 (the pinned build) and the iOS 27.2
  SDK; the job confirmed the driver's symbols in `SCKStreamDriver.o`. CI runs on pushes to `main`,
  on pull requests and on manual runs. Owner review 2026-11-08 (not implemented yet): the main job
  is pinned to `macos-26`, so it keeps testing the iOS 26 SDK path when GitHub moves
  `macos-latest` to Xcode 27; `build-ios27` warns when its Xcode is not build 27B52, and also runs
  the package tests on an iOS 27 simulator (about 3–4 more macOS minutes per run).

## Consequences

- iOS 26 support adds an availability-gated code path. Simulator tests run on iOS 26 (CI and the
  build Mac) and iOS 27.2 (build Mac only, until `build-ios27` runs the iOS 27 simulator tests the
  owner review added). No simulator can run System/App Capture, so its
  behavior is tested on D1/D2 only (Constitution X).
- Test devices are the project device set (FR-032, Clarifications 2026-11-08): D1 iPhone 15
  (iOS 27), D2 iPad Pro M5 (iPadOS 27), D3 iPad A16 (iPadOS 26). The iOS 26 path is covered by D3.
  Their performance is measured, not promised.

## Verification

- [x] Toolchain versions recorded above (2026-11-08); `verify_environment.py` exits 0 on the
      build Mac (it compares version numbers, not the Xcode build). CI pins XcodeGen; its
      Xcode/SDK/Swift gap is documented above.
- [x] Simulator runtimes: CI runs simulator tests on iOS 26.x only (`macos-latest`; run
      42529663444 used iOS 26.5). The `xcode-27` image also has iOS 27.0–27.2 simulator runtimes,
      unused while `build-ios27` only compiles. The build Mac has iOS 27.2 and iOS 26.5 (23F77,
      plus 23F73 under the same identifier).

## Owner review (2026-11-08)

The project owner accepted this ADR on 2026-11-08, after the review described in ADR-0001. The
deployment target is the owner's clarification of 2026-11-07; the toolchain pin (T010), the
iOS 27.0 finding (T035) and the CI implementation details were filled in by agent tasks and are
accepted with it. T035 had also removed an earlier requirement, that CI test both an iOS 26 and an
iOS 27 simulator runtime where available; CI never ran iOS 27 simulator tests, and ruling 4 adds
them.
Rulings:

| # | Ruling | Status |
|---|--------|--------|
| 1 | Explicit `-weak_framework ScreenCaptureKit` for device builds; before any TestFlight upload, a Release build is checked with `otool` and launched on D3. | Not implemented yet |
| 2 | Pin the main CI job to `macos-26` instead of `macos-latest`. | Not implemented yet |
| 3 | `build-ios27` warns, without failing, when its Xcode is not build 27B52. | Not implemented yet |
| 4 | `build-ios27` also runs the package tests on an iOS 27 simulator (about 3–4 more macOS minutes per run). | Not implemented yet |
| 5 | `scripts/verify_environment.py` also requires Xcode build 27B52. | Not implemented yet |
| 6 | Remove the older iOS 26.5 simulator runtime (23F73) from the build Mac, so simulators use 23F77, D3's build. | Not done yet |
