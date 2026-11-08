# ScreenCaptureKit on iOS — platform research (RI-001, RI-004; task T035)

**Status: preliminary.** T035 is not complete: it requires the iOS 27 SDK (Xcode 27), which is
not yet available on GitHub-hosted runners. Fill the open sections from the iOS 27 SDK headers on
the project MacBook (T010 first).

## Findings so far

| # | Finding | Source | Date |
|---|---------|--------|------|
| F1 | `ScreenCaptureKit.framework` is **absent** from the iOS 26.5 SDK (Xcode 26.6). On iOS 26, `#if canImport(ScreenCaptureKit)` is false, so `SCKStreamDriver.swift` is compiled out and System/App Capture shows as unavailable, which is consistent with FR-004/FR-008. | CI probe step, run 42491477885 (`macos-26-arm64`, Xcode_26.6, `iPhoneOS26.5.sdk`) | 2026-11-08 |
| F2 | The newest Xcode on GitHub's `macos-latest` image (`macos-26-arm64`, image 20261028.624) is 26.6. No iOS 27 SDK is installed there, so CI cannot compile the iOS 27 capture path yet. | Same run, "Select newest Xcode" step | 2026-11-08 |

RI-004 implication: F1 supports "iOS 26 = fallbacks only." The **first** iOS version that ships
the framework, and whether it provides app audio, are still open (below).

## Open questions (answer from the iOS 27 SDK headers — T035)

- [ ] First iOS version declaring `SCContentSharingPicker`, `SCStream`, `SCStreamConfiguration`
      (`API_AVAILABLE(ios(…))`). Update FR-008, `@available` in `ScreenCaptureSource.swift` and
      `SCKStreamDriver.swift`, and ADR-0001.
- [ ] Picker modes and selection scope (single app, window, whole display).
- [ ] Audio output types (`SCStreamOutputType` cases on iOS); whether app audio is delivered.
- [ ] `capturesAudio`, `captureMicrophone`, `excludesCurrentProcessAudio` availability on iOS (FR-069).
- [ ] Required Info.plist usage-description key(s) (FR-019).
- [ ] Whether the selected content's identity is exposed (FR-014).
- [ ] Capture indicator behavior with a hidden status bar (FR-089).
- [ ] Background modes or entitlements, if any (RI-003; research R-03 change rule).

The CI probe step re-checks F1 on every run and lists the matching header lines automatically once
a runner ships an SDK that contains the framework.
