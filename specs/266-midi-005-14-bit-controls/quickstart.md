# Quickstart: MIDI-005 MIDI 14-bit Controls

1. Package: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDIHighResolutionTests`.
2. App: `xcodebuild build-for-testing` then `test-without-building -only-testing:projectM-iOSTests/MIDIHighResolutionCoordinatorTests`
   plus `MIDIMappingCoordinatorTests` and `MIDIProfilesCoordinatorTests`, on "MIDI5 iPhone 17".
3. UI: `-only-testing:projectM-iOSUITests/MIDIHighResolutionUITests` (under 30 s): a seeded `cc:0:7` mapping, open its
   Curve row, turn on "14-bit control", the row reads "Linear, 14-bit".
4. `{device}`: on D1 with a physical 14-bit controller (coarse CC n, fine CC n+32), learn Glow intensity: the status
   says "uses 14-bit control"; a slow move changes the glow without visible steps.
