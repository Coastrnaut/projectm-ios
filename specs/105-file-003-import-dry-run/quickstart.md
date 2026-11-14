# Quickstart: FILE-003 Import Dry Run

## Package (host and Linux shape)

```bash
swift test --package-path Packages/PresetLibrary --filter 'PresetArchive|LibraryTreeSnapshot'
swift test --package-path Packages/PresetLibrary -Xswiftc -DCOMPOSITOR_NO_METAL   # Linux shape on the Mac
```

Expected: the fixture table (C1), byte-for-byte cancel and fault rollback, install-equals-plan and
re-validation tests pass, each in about a second.

## App (simulator, iOS 27.2)

```bash
xcodegen generate
xcodebuild test -scheme projectM-iOS -destination 'platform=iOS Simulator,name=FILE3 iPhone 17' \
  -only-testing:projectM-iOSTests/PresetArchiveImportAppTests \
  -only-testing:projectM-iOSTests/SceneArchiveImportPlanTests \
  -only-testing:projectM-iOSUITests/PresetArchiveImportUITests ...
```

Expected: the UI test opens the preview of the DEBUG fixture, taps Cancel and reads the same
library digest before and after, in under 30 s.

## By hand (optional)

Export presets from My Presets (PRE-014), then pick the `.zip` in "Import Preset…": every preset is
counted as identical; Cancel leaves My Presets unchanged.
