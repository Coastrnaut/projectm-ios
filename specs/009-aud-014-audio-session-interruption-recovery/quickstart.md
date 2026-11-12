# Quickstart: validating AUD-014

All commands from the repository root. Simulator results are not device evidence.

## A. Packages on the host

```bash
swift test --package-path Packages/AudioCore
swift test --package-path Packages/CaptureKit
swift test --package-path Packages/CaptureUI
python3 scripts/test_scripts.py && python3 scripts/validate_docs.py && python3 scripts/check_compliance.py
```

Expected: `InterruptionPolicyTests`, `InterruptionRecoveryTests`, `InterruptionPipelineTests`,
`AudioSessionSignalTests` and `InterruptionStringsTests` pass with every existing suite.

## B. Packages and app on the iOS 27.2 simulator

```bash
xcodebuild test -scheme CaptureKit -destination 'id=<udid>' -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO   # in Packages/CaptureKit
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO -only-testing:projectM-iOSUITests/InterruptionUITests
```

`InterruptionUITests` launches with `-uitestSessionEvents`, plays an imported track, posts a
synthetic interruption and checks the status line and the transport before, during and after.

## C. Device: real phone call (final device phase, `{device}`)

Devices: D1 iPhone 15 (iOS 27.0.1) with a SIM or Wi-Fi calling, a second phone to call it; repeat
the FaceTime-audio variant on D2 (iPadOS 27.2) and D3 (iPadOS 26.5). Debug build of
`projectM-iOS`, at least one imported track of 3 minutes or more, silent switch off, volume up.

1. Start the imported track from "Your Audio". Wait for "In-App Playback · Active audio". Note the
   elapsed time when the other phone starts the call.
2. When the call rings: expect the sound to stop, the status "Interrupted" with the explanation,
   the transport showing Play and an elapsed time within 1 s of the noted time.
3. Variant 1, decline: decline the call. Expect playback to continue within 2 s from the held
   position ("Waiting", then "Active audio"). Record whether iOS delivered the end and
   `shouldResume` (Console: the app's lifecycle log, or the diagnostics export's `lifecycleEvents`).
4. Variant 2, answer and return: answer, talk 10 s (the app goes to the background), hang up,
   return to the app. Expect no sound during the call; after the return either playback continues
   from the held position (iOS indicated a resume) or the status stays "Interrupted" and Play
   continues from the held position. Record which.
5. Variant 3, return during the call: answer, switch back to the app while the call is active.
   Expect "Paused"/"Interrupted", no sound, and a Play tap that keeps the track and position
   (it must not end as "In-App Playback failed"). Hang up; record what happens.
6. Variant 4, user pause: pause before the call; decline the call. Expect still paused.
7. Variant 5, seek during the interruption: while it rings, drag the scrubber; decline. Expect
   paused at the new position.
8. Headphones: with wired or Bluetooth headphones, unplug or switch them off while playing: expect
   "Paused — audio route changed" with the explanation; Play continues on the speaker. Unplug
   during a ringing call, then decline: expect no resume.
9. Plug in headphones with another sample rate (or connect AirPlay) while playing: expect playback
   to continue within 1 s at the same position.
10. Record device, OS build, app build, and each variant's result in
    `docs/test-reports/aud-014-interruptions.md`. Nothing is rated "works" without this record.
