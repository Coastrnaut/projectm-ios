# Quickstart: validating AUD-016 Reference tone suite

All commands from the repository root (here: the feature worktree). Simulator: iOS 27.2
"iPhone Air", `77E17861-E687-4274-8A84-14224F32BE3E`. Logs go to `.build/scratch/`; grep them for
`: error: `, `Executed N tests` and `** TEST`.

## A. Determinism on the Mac host (AUD-016-S1 to S4, S6)

```bash
swift test --package-path Packages/AudioCore                             # host
swift test --package-path Packages/AudioCore -Xswiftc -DAUDIOCORE_NO_AVFAUDIO   # Linux path
```

Expected: `ToneMathTests`, `ToneGeneratorTests`, `ReferenceToneCatalogTests` (golden hashes, two
runs), `ReferenceToneOracleTests` (reference DFT bins, onset scan, sweep frequency) and
`ToneAnalyzerDeterminismTests` pass in both runs.

## B. The same hashes in the iOS Simulator (AUD-016-S1)

```bash
cd Packages/AudioCore && xcodebuild test -scheme AudioCore \
  -destination 'id=77E17861-E687-4274-8A84-14224F32BE3E' -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO > ../../.build/scratch/audiocore-sim.log 2>&1
```

The same golden values pass in the simulator: the generator is identical there.

## C. Through the playback graph (AUD-016-S5; US3, US4)

```bash
swift test --package-path Packages/CaptureKit --filter ToneTrack
```

Then the full CaptureKit, CaptureUI and Diagnostics suites on the host and the simulator, and the
Rendering (`Rendering-Package`) and ANGLERendering schemes in the simulator, since they depend on
AudioCore.

## D. The app (US1, AUD-016-S7)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'id=77E17861-E687-4274-8A84-14224F32BE3E' -derivedDataPath .build/dd \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  -only-testing:projectM-iOSUITests/TestSignalsUITests > .build/scratch/app-ui.log 2>&1
```

Manual check in the simulator: chooser → Diagnostics → Test Signals → "Test tone 1 kHz": the
indicator reads "In-App Playback · Test tone 1 kHz · Active audio"; the transport shows 0:10; quit
and relaunch: the chooser, nothing playing.

## E. Device phase `{device}` (AUD-016-S8, final phase only)

On D1, D2 and D3: each signal kind audible on the speaker and on headphones; status "Active audio"
(silence: "Audio received — silent"); a phone call or Siri interruption and unplugging headphones
behave as for an imported track (AUD-014). Record results in `docs/test-reports/`.
