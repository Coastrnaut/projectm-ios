# Quickstart: validating PRE-015

Run from the feature checkout. Simulator: iOS 27.2 "iPhone 18 Pro" (pick by runtime; UDID in
the session notes). Logs go to `.build/scratch/`; grep them for `: error: `, `Executed`,
`** TEST`.

## A. Package (host)

```bash
swift test --package-path Packages/PresetLibrary
```

Expect the PRE-012 suites plus `UserPresetDuplicationTests`, `UserPresetEditingTests` and
`UserPresetsMigrationTests` to pass. Proves R2-R8, R11-R15, R19, R21, R22 at the store layer
(S3, S4, S5).

## B. Regression suites (simulator, unchanged packages)

```bash
cd Packages/Rendering && xcodebuild test -scheme Rendering-Package -destination 'id=<udid>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO
cd Packages/ANGLERendering && xcodebuild test -scheme ANGLERendering -destination 'id=<udid>' …
```

## C. App unit and UI tests (simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO -only-testing:projectM-iOSTests \
  -only-testing:projectM-iOSUITests/UserPresetEditingUITests \
  -only-testing:projectM-iOSUITests/UserPresetsUITests \
  -only-testing:projectM-iOSUITests/PresetCollectionsUITests \
  -only-testing:projectM-iOSUITests/VisualizerUITests
```

- `UserPresetDuplicationAppTests`: all 28 Included presets: bundle bytes and the index hash equal
  before, after duplicate, after edit and save (S1); the copy's file changes (S2); the bundled
  preset loads from the bundle (S2); favorites and collections naming the bundled id unchanged
  (R20); lock and refund hold (S4).
- `UserPresetEditingUITests`: duplicate from a row and from the controls; edit, failing save
  (reason shown, previous text kept), successful save, discard prompt; the editor at the largest
  accessibility text size (S6).

Known environmental failure: `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (needs the
full library, not checked out in a feature worktree).

## D. Device `{device}`

S7: on D1, duplicate a preset, replace its text with a 524,288-byte valid preset (paste), close
and reopen the editor; it must open in under 2 s. Not run by this feature (final device phase).
