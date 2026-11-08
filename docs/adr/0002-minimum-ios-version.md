# ADR-0002: Minimum iOS Version and Toolchain

- **Status**: Accepted for deployment target; toolchain pin pending Gate 0
- **Date**: 2026-11-07
- **Spec**: Clarifications 2026-11-07, FR-008, FR-032 · **Research**: R-01

## Context

The stakeholder clarified that the app must run on iOS/iPadOS 26+, on any iOS 26-capable device,
with System/App Capture only where the OS provides it.

## Decision

- **Deployment target**: iOS 26.0 and iPadOS 26.0, universal app.
- **SDK**: the iOS 27 SDK (or newer), needed to compile the System/App Capture adapter.
- **Feature gating**: System/App Capture is availability-gated (ADR-0001); all other features work
  on iOS 26.
- **Toolchain pin** (filled at Gate 0): Xcode `TBD`, SDK `TBD`, Swift `TBD`, XcodeGen `TBD`,
  CMake `TBD`. The same versions go in `.github/workflows/ios-ci.yml` and
  `scripts/verify_environment.py`.

## Consequences

- iOS 26 support adds an availability-gated code path. CI must test both an iOS 26 and an iOS 27+
  simulator runtime where available.
- The minimum test devices are the oldest obtainable iOS 26-capable iPhone and iPad (FR-032).
  Their performance is measured, not promised.

## Verification

- [ ] Toolchain versions recorded above and in CI.
- [ ] Both simulator runtimes are available on the CI image, or the gap is documented.
