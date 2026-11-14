# Quickstart: REC-004 Recording audio mux

## Host (Mac)

```bash
swift test --package-path Packages/AudioCore --filter RecordingTapTests
swift test --package-path Packages/Compositor --filter 'RecordingAudio'
```

Expected: the policy and timeline tests pass; `RecordingAudioMuxTests.testOwnedAudioClickAlignsWithFlash`
reports the click and flash within 20 ms; the consent, system-capture and switch tests pass.

## Simulator (own simulator "REC4 iPhone 17", iOS 27.2)

Build for testing, then run `projectM-iOSTests/RecordingAudioAppTests` and
`projectM-iOSUITests/RecordingAudioUITests` with `test-without-building`.
Expected: the setting defaults off and persists; the decision, status texts and early end pass; the
UI test toggles "Include microphone audio" in Settings → Recording and reads the new status.

## Device `{device}` (last stage)

1. Import a song into the library with a sharp transient (a click track), start In-App Playback, show a spectrum, record 10 s, save.
2. Open the file in Photos or QuickTime and step frame by frame: the flash for the click and the click are within 40 ms (REC-004-S5).
3. Switch to Microphone with the setting off: record; the file has no audio track. Turn the setting on (permission granted): the file has the room sound.
4. On D1/D2, System/App Capture: record; the file has no audio track.
