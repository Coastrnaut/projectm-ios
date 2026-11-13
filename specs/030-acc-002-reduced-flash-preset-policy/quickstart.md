# Quickstart: ACC-002 Reduced Flash Preset Policy checks

Run from the repository root on the Mac Studio. Budgets: owner rule 7.

## 1. Classifier parity and index (any OS)

```bash
python3 scripts/test_scripts.py          # includes the fixture parity and index-field tests
swift test --package-path Packages/PresetLibrary --filter PresetFlashRiskTests
swift test --package-path Packages/PresetLibrary
```

Expected: the high-flash fixture has rules, the calm fixture none, both languages agree on every
fixture (ACC-002-S1); the package suite stays under a minute.

## 2. Corpus count (information)

```bash
python3 scripts/build_preset_index.py --force --out .build/scratch/acc002-index \
  --packs-dir <checkout with Vendor/presets initialized>/Vendor/presets
python3 -c "import json;d=json.load(open('.build/scratch/acc002-index/PresetIndex.json'));print(sum(1 for p in d['presets'] if p.get('flash')), len(d['presets']))"
```

## 3. App (simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<UDID>' \
  -derivedDataPath .autonomous/derived-data-acc-002 CODE_SIGNING_ALLOWED=NO \
  -only-testing:projectM-iOSTests -only-testing:projectM-iOSUITests/FlashPolicyUITests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 > .build/scratch/acc002-app.log 2>&1
grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:" .build/scratch/acc002-app.log
```

Expected: `FlashPolicyTests` pass; the UI test imports the high-flash fixture, chooses it with
Reduce flashing on, sees the "May flash" alert while the previous preset is still current,
cancels, then loads it with Load Anyway, in under 30 s (ACC-002-S2). In a worktree without preset
submodules `PresetTests.testBundledIncludedScopeMatchesRelease1_0` may fail for that reason only.

## 4. Device `{device}` (last stage, not run by this row)

On D1 with Reduce flashing on: browse a pack, confirm "May flash" rows read correctly with
VoiceOver, Random 50 times without a flagged preset, the warning on a flagged pick at the largest
text size.
