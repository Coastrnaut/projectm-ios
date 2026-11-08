# ADR-0002: Minimum iOS Version and Toolchain

- **Status**: Accepted for deployment target; toolchain pin pending Gate 0
- **Date**: 2026-11-07
- **Spec**: Clarifications 2026-11-07, FR-008, FR-032 · **Research**: R-01

## Context

The stakeholder clarified that the app must run on iOS/iPadOS 26+, on any iOS 26-capable device,
with System/App Capture only where the OS provides it.

## Decision

- **Deployment target**: iOS 26.0 and iPadOS 26.0, one app for the iPhone and iPad device family.
- **SDK**: the iOS 27 SDK (or newer), needed to compile the System/App Capture adapter.
- **Feature gating**: System/App Capture is availability-gated (ADR-0001); all other features work
  on iOS 26.
- **Toolchain pin** (recorded 2026-11-08, task T010): Xcode `27.2` (build 27B52), SDK `27.2`
  (iOS), Swift `6.4.2`, XcodeGen `2.46.0`, CMake `4.4.5`. `scripts/verify_environment.py` reads
  these values and must exit 0 on the build Mac.

- **Build machine of record**: the project Mac (macOS 27.2, Apple silicon), which has Python 3.15
  (scripts need 3.10+) and simulator runtimes for iOS 27.2 and iOS 26.5 (23F77, the same build
  as D3). Every `{mac}` build or test result is reported against this pin.
- **CI**: GitHub's `macos-latest` image (`macos-26-arm64`, image 20261102.0473.1) offers Xcode
  26.0–26.6 only, with the iOS 26.5 SDK and iOS 26.x simulator runtimes. CI therefore cannot
  match the Xcode/SDK/Swift pin yet: it installs the pinned XcodeGen, runs
  `verify_environment.py` as a warning, and covers the iOS 26 path. The iOS 27 SDK path
  (System/App Capture) is compiled and tested only on the build Mac until a runner image ships
  Xcode 27. Re-pin CI to that image when it exists.

## Consequences

- iOS 26 support adds an availability-gated code path. CI must test both an iOS 26 and an iOS 27+
  simulator runtime where available.
- Test devices are the project device set (FR-032, Clarifications 2026-11-08): D1 iPhone 15
  (iOS 27), D2 iPad Pro M5 (iPadOS 27), D3 iPad A16 (iPadOS 26). The iOS 26 path is covered by D3.
  Their performance is measured, not promised.

## Verification

- [x] Toolchain versions recorded above (2026-11-08); `verify_environment.py` exits 0 on the
      build Mac. CI pins XcodeGen; its Xcode/SDK/Swift gap is documented above.
- [x] Simulator runtimes: CI has iOS 26.x only (gap documented above); the build Mac has
      iOS 27.2 and iOS 26.5.
