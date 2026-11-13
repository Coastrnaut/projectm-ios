# Quickstart: validating PRE-014

Run from the repository (or the feature worktree). Simulator: iOS 27.2 "iPhone 18 Pro".

## A. Packages (macOS host; Linux in CI)

```bash
swift test --package-path Packages/LocalPortability
swift test --package-path Packages/PresetLibrary
```

Expected: all pass, including the round trip (`UserPresetArchiveTests.testRoundTrip…`), the
golden hash, every tamper case and the ADR-0008 exclusion tests.

## B. Interoperability (once, evidence)

Write the golden fixture archive (`EXPORT_FIXTURE_OUT=<path> swift test --filter
testWriteFixtureForInteroperability`), then:

```bash
unzip -t <path>                      # "No errors detected"
python3 -I -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip(), z.namelist())" <path>
```

## C. App on the simulator

```bash
xcodegen generate
xcodebuild -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO test -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/UserPresetExportUITests
```

Expected: app unit tests pass (known environmental failure:
`PresetTests.testBundledIncludedScopeMatchesRelease1_0` without the full library);
`UserPresetExportUITests` imports a preset, exports it, sees the share sheet, and reads the
archive copied by `-uitestExportPresetTo`.

## D. Manual (final device phase, `{device}`)

On D1: import two presets, duplicate an Included preset and a pack preset (unlocked), open My
Presets → Export…: the pack copy is not listed and the footer says why; Export → Save to Files;
open the ZIP in Files: `manifest.json` and three `.milk` files (two imports, the Included copy).
