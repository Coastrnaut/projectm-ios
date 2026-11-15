# MED-005 Video reverse playback — test report

Feature: `specs/284-med-005-video-reverse-playback/` (roadmap row MED-005, P3, L). Acceptance, verbatim: "Short
fixture reverses frame order and unsupported clips show clear error."

Run 2026-11-15 on the Mac Studio (Xcode 27.2), branch `feature/med-005`. Simulator results are never device evidence
(Constitution X); the device task MED-005-T20 is open.

## Acceptance proof

| Criterion | Test | What it asserts | Result |
|---|---|---|---|
| Short fixture reverses frame order | `VideoReverseLayerTests.testTwelvePictureFixtureReversesFrameOrderThroughTheCompositor` | A generated 12-picture H.264 clip (grey level = index), reverse on, 26 frames at injected times k/30 s + 5 ms read back through the real compositor: `[11, 10, …, 0, 11, …, 0, 11, 10]` | Pass |
| Same rule, pure | `VideoReverseTests.testTwelvePicturesPlayInDescendingOrderAndWrap`, `testRegionStartAndSpeedArePureFunctionsOfVideoTime` | Descending order, wrap, region [0.5 s, 1 s) out → in → out, start at the shown picture without a jump, 0.5× speed | Pass |
| Unsupported clips show a clear error, forward continues | `VideoReverseLayerTests.testUnsupportedClipsReportTheirReasonAndKeepPlayingForward` | A 2 s clip over a 1 s limit (track facts) → `.unsupported(.tooLong)` and forward pictures 0…7; a corrupt copy → `.unsupported(.undecodable)`, the compositor keeps drawing | Pass |
| Messages | `VideoReverseTests.testOnlyShortClipsUpTo1080pAreSupportedWithClearMessages`, `VideoReverseAppTests.testUnsupportedClipsShowAndAnnounceTheirSentenceOnce` | Exact sentences; caption shown while Reverse is on, announced once, cleared by Reverse off and a new video | Pass |
| Memory budget | `VideoReverseTests.testLargestSupportedClipFitsEachDeviceClassBudget`, `VideoReverseLayerTests.testSmallBudgetHoldsAndSuspendReleasesTheCache` | 30 s 1080p 60 fps through the builder: 900 pictures, peak ≤ 32 / 64 / 128 MB (cached size 125 × 70 / 177 × 99 / 252 × 141); a real 64 KB build peaks within it; suspend releases, resume rebuilds | Pass |
| Settings persistence | `VideoReverseAppTests` (4 tests), `SettingsTests`, `LibraryBackupAppTests`, LibraryBackup package | `settings.video.reverse` = `{id}` survives a relaunch, cleared by a new video and Remove Video, foreign values removed; listed for the UI-test reset, excluded from backups, erased with media | Pass |
| App + UI | `VideoReverseUITests.testReverseSwitchPlaysTheSeededClipBackwards` | Settings → Video → Reverse on; the `videoReverse` probe reports `playing` with indices `[32, 29, 26, 20]` | Pass (24.5 s) |

## Commands and counts

| Command | Result |
|---|---|
| `swift test --filter VideoReverse` (Packages/Compositor) | 11 tests, 0 failures, 0.6 s |
| `swift test --filter Video` (Packages/Compositor) | 56 tests, 0 failures, 5.1 s |
| `swift build --build-tests -Xswiftc -DCOMPOSITOR_NO_METAL` (Linux shape) | builds |
| `swift test` (Packages/LibraryBackup) | 87 tests, 0 failures, 8.0 s |
| App unit tests (VideoReverseAppTests, SettingsTests, LibraryBackupAppTests, VideoSpeedTests, VideoStoreTests, LibraryEraseAppTests), iOS 27.2 simulator | 35 tests, 0 failures, 0.8 s |
| `VideoReverseUITests`, iOS 27.2 simulator | 1 test, passed, 24.5 s |
| Repo checks, `check_privacy_manifest`, `check_network_symbols` | OK |

## Open

- MED-005-T20 `{device}`: on D1 and D3, a 30 s 1080p clip reverses within the device class budget (Xcode memory
  gauge) and a 2-minute clip shows the 30-second message while it plays forward.
