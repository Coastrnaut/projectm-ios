# Quickstart: AUD-011 Input Noise Gate

1. Package tests (host and Linux shape):
   `swift test --package-path Packages/AudioCore --filter NoiseGate` and the same with
   `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`. Expect the silence fixture all zeros, the opening within
   attack + 512 frames, no chatter, hold/release timing, bit-exact pass-through, the seam test.
2. App (simulator "AUD11 iPhone 17", iOS 27.2): `xcodegen generate`, then `xcodebuild test` with
   `-only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/NoiseGateUITests` (plus the
   InputTrim and ChannelSelection UI tests). Expect the toggle off, the slider disabled at
   "−50 dBFS", enabled after the toggle.
3. Device (`{device}`, final roadmap phase): D1, Microphone, a quiet room with the gate on; the
   bars stay still until music plays; plug headphones and take a call; the gate keeps working.
