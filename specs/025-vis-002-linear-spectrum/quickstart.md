# Quickstart: validating VIS-002

Run from the repository (or the feature worktree). Logs go to `.build/scratch/`.

1. Package, host and Linux shape (CPU and GPU tests; GPU tests skip without Metal):
   ```bash
   swift test --package-path Packages/VisualGenerators
   swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
   ```
   Expected: every test passes, including `LinearSpectrumLayoutTests`, `PeakCapTrackerTests`,
   `LinearSpectrumRenderTests` (skipped in the Linux shape) and `LinearSpectrumFlashTests`.
2. Simulator (iOS 27.2 "iPhone Air", udid `77E17861-E687-4274-8A84-14224F32BE3E`), from
   `Packages/VisualGenerators`:
   ```bash
   xcodebuild test -scheme VisualGenerators -destination 'id=77E17861-E687-4274-8A84-14224F32BE3E' \
     -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO > ../../.build/scratch/vis002-sim.log 2>&1
   ```
3. App: `xcodegen generate`, then the app unit tests and
   `-only-testing:projectM-iOSUITests/NativeVisualUITests -only-testing:projectM-iOSUITests/LinearSpectrumUITests`.
4. Look at it: start the reference track (`-autostart inAppPlayback`), Settings → Visual → Linear
   Spectrum; switch Orientation; take a simulator screenshot of each orientation.
5. `{device}`: the same on D1-D3 in the roadmap's final device phase (GPU, frame time).
