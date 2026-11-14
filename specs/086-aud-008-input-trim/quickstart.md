# Quickstart: AUD-008 Input Trim

Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min, UI test < 30 s.

1. Processing (host, then the Linux shape):
   `swift test --package-path Packages/AudioCore --filter InputTrimTests`
   `swift test --package-path Packages/AudioCore -Xswiftc -DAUDIOCORE_NO_AVFAUDIO --filter InputTrimTests`
   Expect: RMS steps equal the trim within 0.05 dB, 0 dB bit-exact, +24 dB bounded and finite, ramp
   bound held, projectM's ring bit-identical with a +24 dB trim on the tap (contract C1-C4).
2. Bands and oscilloscope:
   `swift test --package-path Packages/VisualGenerators --filter InputTrimBandTests` (and with
   `-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`).
3. App (simulator "AUD8 iPhone 17", iOS 27.2): `xcodegen generate`, then `xcodebuild test` with
   `-only-testing:projectM-iOSTests/InputTrimSettingTests` and
   `-only-testing:projectM-iOSUITests/InputTrimUITests`: set +24 dB, relaunch, +24 dB shown; Reset →
   0 dB.
4. `{device}` (final roadmap phase): on D1, microphone source, trim +12 dB: bars react more; route
   change (headphones) and an interruption (phone call) keep the trim and the analysis running.
