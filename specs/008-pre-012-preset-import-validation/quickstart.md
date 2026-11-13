# Quickstart: validating PRE-012

All commands from the repository root. Simulator results are not device evidence.

## 1. Package (macOS host)

```bash
swift test --package-path Packages/PresetLibrary
```

Expect all tests to pass, including `MilkdropPresetValidatorTests`, `PresetMutationSweepTests`
(60 seeded variants by default, six per mutation kind; the full 600-variant S2 sweep runs with
`PRESET_MUTATION_SWEEP_FULL=1`, owner rule 7, 2026-11-13), `UserPresetStoreTests` (golden `user-presets-v1.json`), and
`UserPresetLibraryTests` (trial outcomes, both "app died" recoveries). The built-in corpus check
(S7) runs only when `Vendor/presets/cream-of-the-crop` is populated and is skipped otherwise.

## 2. Real engine (iOS 27.2 simulator)

```bash
cd Packages/ANGLERendering && xcodebuild test -scheme ANGLERendering -destination 'id=<udid>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/angle.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" ../../.build/scratch/angle.log
```

`PresetTrialRunnerTests`: a valid preset passes; broken equations fail with the engine's message;
presets at the static limits do not crash; a nested-loop preset times out; the visible renderer's
frame count keeps rising and its preset is unchanged (S3).

## 3. App (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination 'id=<udid>' \
  -derivedDataPath .build/dd -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
  CODE_SIGNING_ALLOWED=NO -only-testing:projectM-iOSUITests/UserPresetsUITests \
  > .build/scratch/ui.log 2>&1
```

`UserPresetsUITests`: import a valid preset, play it, Next stays in My Presets, relaunch and play
again (S5); import a preset with broken equations and a binary file, see the alert and the
Quarantine rows with reasons while the current preset name is unchanged; delete from Quarantine.

## 4. By hand ({device}, final device phase)

On D1: Files → pick a `.milk` file → My Presets; pick a JPEG renamed to `.milk` → Quarantine;
VoiceOver reads each row and reason; largest text size shows no clipped text.

## 5. Gates

```bash
python3 scripts/validate_docs.py && python3 scripts/check_compliance.py && python3 scripts/test_scripts.py
```
