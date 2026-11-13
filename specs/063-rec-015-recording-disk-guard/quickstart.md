# Quickstart: validating REC-015

Prerequisites: the worktree's `xcodegen generate`, preset submodules, a dedicated iOS 27.2 simulator.

1. Rules and fixture (host + Linux shape):
   `swift test --package-path Packages/Compositor --filter FrameRecordingTests` — estimate, policy,
   classifier, offline recording stopped at frame k (k frames, increasing times), injected disk full
   (no file). Linux shape: add `--scratch-path .build/linuxshape -Xswiftc -DCOMPOSITOR_NO_METAL
   -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
2. App unit tests: `xcodebuild test … -only-testing:projectM-iOSTests` (VideoRecordingAppTests guard
   cases).
3. UI test: `-only-testing:projectM-iOSUITests/RecordingDiskGuardUITests` — `low`: Record refused
   with the notice; `dropAfter:3`: recording stops with the low-storage notice, the Recording ready
   panel appears and the probe reads back a video with frames.
4. Privacy: `python3 scripts/check_privacy_manifest.py <Debug-iphonesimulator/projectM-iOS.app>` →
   Disk space found and declared (E174.1), OK; `python3 scripts/test_scripts.py`.
5. Device (`{device}`, owner): on D1 nearly full, or a long recording, the guard stops the recording
   with "Recording stopped because storage is almost full." and the offered file plays.
