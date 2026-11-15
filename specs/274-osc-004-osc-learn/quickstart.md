# Quickstart: OSC-004 OSC Learn

1. Package: `swift test --package-path Packages/PerformanceControl --filter OSCLearnTests`.
2. App: `-only-testing:projectM-iOSTests/OSCLearnCoordinatorTests` on "OSC4 iPhone 17".
3. UI: `-only-testing:projectM-iOSUITests/OSCLearnUITests` (arm, inject through `-uitestFakeOSC`, bound).
4. `{device}` D1 (OSC-004-T14): OSC on, D1 and a tablet with an OSC app on the same Wi-Fi; Settings › OSC › OSC
   Routes › Learn beside Glow intensity; move a fader: the status names the fader's address, a "Your alias" row
   appears, and the fader drives the glow. Repeat with "Only approved devices" on and the tablet not approved:
   nothing is bound and learn times out after 10 s.
