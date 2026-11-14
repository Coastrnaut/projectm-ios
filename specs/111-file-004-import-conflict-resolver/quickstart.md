# Quickstart: FILE-004 Import Conflict Resolver

## Packages (host; CI runs them on Linux too)

```bash
swift test --package-path Packages/PresetLibrary --filter 'PresetArchive|LibraryTreeSnapshot'
swift test --package-path Packages/ShowControl --filter ShowSceneImport
```

Expected: the ID table, mixed choices, Skip byte-identity, Replace fault and crash loops,
re-validation, each test in about a second.

## App (own simulator "FILE4 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild test -scheme projectM-iOS -destination 'platform=iOS Simulator,name=FILE4 iPhone 17' \
  -only-testing:projectM-iOSTests/PresetArchiveConflictAppTests \
  -only-testing:projectM-iOSTests/PresetArchiveImportAppTests \
  -only-testing:projectM-iOSUITests/PresetArchiveImportUITests \
  -only-testing:projectM-iOSUITests/PresetArchiveConflictUITests ...
```

Expected: the UI test switches the conflict row from Keep both to Skip and Replace, sees the
install count and outcome follow, cancels, and reads the same library digest, in under 30 s.
