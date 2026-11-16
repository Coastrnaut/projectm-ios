# QA-011 device acceptance: D1 session B05-B06-effects

Automated owner-session steps on the device (Apps/projectM-iOS/DeviceUITests). Log SHA-256 `ff2c1c77a62962cce02741b8586af4ee8552ca0bd3bc8a3fc61eff676829c90f`; 8 of 8 tests passed.

| Task | Frame-rate steps | Median fps | Lowest 1 s fps |
|---|---|---|---|
| ANL-013-T14 | 0 | — | — |
| AUD-006-T39 | 0 | — | — |
| AUD-009-T13 | 0 | — | — |
| CAM-012-T13 | 0 | — | — |
| FX-010-T17 | 2 | 59–59 | 57 |
| FX-014-T18 | 4 | 58–59 | 56 |
| FX-016-T17 | 6 | 58–60 | 56 |
| PERF-011-T22 | 2 | 60–60 | 57 |

| Test | Result | Seconds |
|---|---|---|
| B06CameraDeviceTests.testCAM012StopCameraReleasesIt | passed | 29.1 |
| B06CameraDeviceTests.testFX010EchoOverCamera | passed | 63.0 |
| B06CameraDeviceTests.testFX014EdgeOutlineOverCamera | passed | 120.6 |
| B06CameraDeviceTests.testFX016LensDistortionOverCamera | passed | 180.9 |
| B02ShowsDeviceTests.testPERF011ReturnAfterRotationWhileAway | passed | 43.3 |
| B05AudioDeviceTests.testANL013PhaseInvertedFeedWarns | passed | 18.8 |
| B05AudioDeviceTests.testAUD006PauseStaysPausedAcrossBackground | passed | 21.8 |
| B05AudioDeviceTests.testAUD009ChannelSelectionFollowsTheChosenChannel | passed | 37.8 |
