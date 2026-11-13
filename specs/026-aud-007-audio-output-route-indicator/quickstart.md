# Quickstart: validate AUD-007

## Host (macOS; the pure parts also on the Linux path)

```bash
swift test --package-path Packages/CaptureKit --filter 'AudioRoute'
swift test --package-path Packages/CaptureKit -Xswiftc -DAUDIOCORE_NO_AVFAUDIO --filter 'AudioRoute'
swift test --package-path Packages/CaptureUI --filter RouteStringsTests
swift test --package-path Packages/CaptureKit --filter AudioSourceContractTests   # QA-007 stays green
```

Expected: every route test passes, each in about a second or less.

## Simulator (iOS 27.2, iPhone 18 Pro)

From each package folder:

```bash
xcodebuild test -scheme CaptureKit -destination 'id=<udid>' -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO > .build/scratch/ck.log 2>&1
```

Expected: `SystemAudioRouteTests` pass (SDK port constants map as contracts/route-model.md says; the
observer turns a posted route change into a monitor change; a lost output both holds the backend and
reads "— paused").

App: `xcodegen generate`, then `xcodebuild test` with
`-only-testing:projectM-iOSTests/RouteCoordinatorTests -only-testing:projectM-iOSUITests/RouteIndicatorUITests
-only-testing:projectM-iOSUITests/StatusUITests`. Expected: the UI test sees "Audio output: Speaker",
then "Audio output: Headphones" with "Now playing through Headphones", then after the unplug
"Headphones disconnected — paused" and the source indicator ending in "Paused".

## Device (`{device}`, final phase; D1)

1. Install a Debug or Release build; start In-App Playback (the reference track) on the speaker.
2. Tap the visualizer to show the controls: the route indicator reads "Output: Speaker" (or the
   receiver/speaker name iOS gives).
3. Plug in wired headphones (or connect Bluetooth headphones): within 1 s the indicator shows their
   name and "Now playing through <name>" appears.
4. Unplug them (or disconnect): playback pauses, the banner reads "Paused — audio route changed", the
   explanation reads "<name> disconnected — paused" and the indicator returns to the speaker.
5. With VoiceOver on, repeat 3: the explanation is announced; repeat 4: AUD-014's hold announcement is
   heard once.
6. Start Microphone mode, plug in a headset with a microphone: the indicator shows "Input: <name>".
7. At every step, no route text names System/App Capture, Microphone, In-App Playback or any app.
Record the result (pass/fail per step, iOS version, headphones used) in
`docs/test-reports/route-indicator.md`.
