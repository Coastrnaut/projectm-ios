# Quickstart: MIDI-013 MIDI Panic

1. Package: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE --filter MIDIPanicTests`.
2. App: `xcodebuild build-for-testing` then `test-without-building -only-testing:projectM-iOSTests/MIDIPanicCoordinatorTests`
   plus the existing MIDI coordinator suites, on the feature's own simulator.
3. UI: `-only-testing:projectM-iOSUITests/MIDIPanicUITests` (under 30 s): Settings opens at MIDI, plug Fake Keys, Hold
   Note → "1 held", MIDI Panic → "0 held", Hold Note again → "1 held", ⌘⇧M → "0 held".
4. `{device}`: on D1 with a physical controller, map a pad to "Black out while held", hold it, unplug nothing, press
   MIDI Panic: the output returns and the pad works again.
