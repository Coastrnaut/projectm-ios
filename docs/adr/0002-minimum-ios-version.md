# ADR-0002: Minimum iOS Version and Toolchain

- **Status**: Accepted (2026-11-08): deployment target; toolchain pin (T010); first OS with System/App
  Capture = iOS/iPadOS 27.0 (Gate 0, T035, RI-004)
- **Date**: 2026-11-07 (accepted 2026-11-08)
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
  ScreenCaptureKit annotation of the iOS 27.2 SDK (ADR-0001; RI-004). The device build weak-links
  ScreenCaptureKit (deployment target 26.0; checked with `otool -L`), so it should load on iOS 26,
  where the framework is absent; confirmed only when CaptureLab runs on D3. All other features work
  on iOS 26.
- **Toolchain pin** (recorded 2026-11-08, task T010): Xcode `27.2` (build 27B52), SDK `27.2`
  (iOS), Swift `6.4.2`, XcodeGen `2.46.0`, CMake `4.4.5`. `scripts/verify_environment.py` reads
  these values and must exit 0 on the build Mac.

- **Build machine of record**: the project Mac (macOS 27.2, Apple silicon), which has Python 3.15
  (scripts need 3.10+) and simulator runtimes for iOS 27.2 and iOS 26.5 (23F77, the same build
  as D3). Every `{mac}` build or test result is reported against this pin.
- **CI**: the main job runs on GitHub's `macos-latest` image (`macos-26-arm64`, image
  20261102.0473.1): Xcode 26.0–26.6, the iOS 26.5 SDK and iOS 26.x simulator runtimes. It covers the
  iOS 26 path, installs the pinned XcodeGen, and runs `verify_environment.py` as a warning, because
  the Xcode/SDK/Swift pin cannot match there. GitHub also offers an `xcode-27` image (`runs-on:
  xcode-27`, a public preview announced 2026-07-16 in actions/runner-images#14404; image
  20261026.0314.1 has Xcode 27.2 as release candidate 27B48, not the pinned 27B52, and the iOS
  27.0–27.2 SDKs). Owner ruling 2026-11-08: the CI job `build-ios27` (first run pending) runs there
  on every run, picks the newest Xcode 27 that can build for iOS devices, and compiles CaptureKit
  (including the System/App Capture driver) and CaptureLab for iOS devices, at the cost of extra
  macOS minutes (10× quota on this private repository). It only compiles; the iOS 27 path is tested
  on the build Mac and on devices.

## Consequences

- iOS 26 support adds an availability-gated code path. Simulator tests run on iOS 26 (CI and the
  build Mac) and iOS 27.2 (build Mac only). No simulator can run System/App Capture, so its
  behavior is tested on D1/D2 only (Constitution X).
- Test devices are the project device set (FR-032, Clarifications 2026-11-08): D1 iPhone 15
  (iOS 27), D2 iPad Pro M5 (iPadOS 27), D3 iPad A16 (iPadOS 26). The iOS 26 path is covered by D3.
  Their performance is measured, not promised.

## Verification

- [x] Toolchain versions recorded above (2026-11-08); `verify_environment.py` exits 0 on the
      build Mac. CI pins XcodeGen; its Xcode/SDK/Swift gap is documented above.
- [x] Simulator runtimes: CI has iOS 26.x only (gap documented above); the build Mac has
      iOS 27.2 and iOS 26.5.
