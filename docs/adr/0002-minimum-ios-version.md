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
- **Toolchain pin** (filled at Gate 0): Xcode `TBD`, SDK `TBD`, Swift `TBD`, XcodeGen `TBD`,
  CMake `TBD`. The same versions go in `.github/workflows/ios-ci.yml` and
  `scripts/verify_environment.py`.

## Consequences

- iOS 26 support adds an availability-gated code path. CI must test both an iOS 26 and an iOS 27+
  simulator runtime where available.
- Test devices are the project device set (FR-032, Clarifications 2026-11-08): D1 iPhone 15
  (iOS 27), D2 iPad Pro M5 (iPadOS 27), D3 iPad A16 (iPadOS 26). The iOS 26 path is covered by D3.
  Their performance is measured, not promised.

## Verification

- [ ] Toolchain versions recorded above and in CI.
- [ ] Both simulator runtimes are available on the CI image, or the gap is documented.
