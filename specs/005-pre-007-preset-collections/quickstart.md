# Quickstart: validating PRE-007 Preset collections

All commands run from the repository root. Simulator and host results are not device evidence.

## 1. Package logic (macOS host; also valid on Linux)

```bash
swift test --package-path Packages/PresetLibrary
```

Expected: all tests pass, including `PresetCollectionTests`, `PresetCollectionStoreTests`,
`PresetCollectionsFileTests` and `PresetCollectionScopeTests`. These cover S1-S7 and S9 at the
logic level (see [data-model.md](data-model.md) and
[contracts/preset-collections.md](contracts/preset-collections.md)).

## 2. Package on the iOS simulator

```bash
(cd Packages/PresetLibrary && xcodebuild test -scheme PresetLibrary -destination 'id=<iOS 27.2 simulator udid>')
```

## 3. App unit tests and UI tests (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  -derivedDataPath .build/dd -only-testing:projectM-iOSTests/PresetCollectionsCoordinatorTests \
  -only-testing:projectM-iOSTests/PresetTests -only-testing:projectM-iOSUITests/PresetCollectionsUITests \
  > .build/pre-007-app.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" .build/pre-007-app.log
```

Expected: `** TEST SUCCEEDED **`. In a worktree without the preset submodules,
`PresetTests.testBundledIncludedScopeMatchesRelease1_0` fails for an environmental reason (it
expects the full library) and the existing `PresetLibraryUITests` need the full library; run those
on the integration checkout.

## 4. Manual check on a simulator (about two minutes)

1. Start In-App Playback, open Presets, open **Collections**, tap **+**, name it "Friday set".
2. Go back, open **Included**, long-press a preset → **Add to Collection…** → "Friday set"; repeat
   for two more presets.
3. Open "Friday set": three presets in the order added. Long-press the last → **Move Up**; or tap
   **Edit** and drag.
4. Tap a preset: the browser closes, the scope line reads "Friday set · 3"; Next and Previous
   follow the order shown and wrap.
5. Stop the app, start it again: same collection, same order, scope line still "Friday set · 3".
6. Delete the collection: the presets are still in Included, stars unchanged, the scope line
   falls back to "Included · 28".

## 5. Compliance and docs

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
```

## 6. Final device stage `{device}` (not run during implementation)

S11: install over the previous build on D1-D3 and confirm collections are intact; reorder with
VoiceOver using the "Move Up"/"Move Down" actions.
