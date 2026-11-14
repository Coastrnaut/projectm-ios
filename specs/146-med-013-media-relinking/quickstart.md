# Quickstart: MED-013 Media Asset Relinking

## Package tests (host; CI also runs them on Linux)

```bash
swift test --package-path Packages/LocalPortability --filter "MediaRelink|MediaFolderScan|ContentAddressed"
swift test --package-path Packages/SceneFormat --filter SceneMediaReference
swift test --package-path Packages/ShowControl --filter ShowMediaRelink
swift test --package-path Packages/LibraryBackup --filter LibraryErase
```

## App tests (simulator "MED13 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild build-for-testing -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=MED13 iPhone 17' \
  -derivedDataPath .autonomous/derived-data-med-013 CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/MediaRelinkAcceptanceTests
xcodebuild test-without-building ... -only-testing:projectM-iOSUITests/MissingMediaUITests
```

## By hand (simulator)

1. Launch with `-uitestMissingMediaSeed`: two scenes and a cue use a photo whose file is gone.
2. Step to cue 1: the "Missing media" tile shows.
3. Settings → Storage → Missing Media: one photo "used by 2 scenes".
4. Find Missing Media in Folder… (the DEBUG seed points it at its fixture folder): "Relinked 1".
