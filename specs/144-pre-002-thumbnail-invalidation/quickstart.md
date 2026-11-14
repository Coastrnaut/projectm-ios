# Quickstart: validating PRE-002

## Package (macOS host; the same suite runs on Linux in CI)

```bash
swift test --package-path Packages/PresetLibrary --filter PresetThumbnail
```

Expect `PresetThumbnailInvalidationTests` to pass: acceptance A/B/C (S1), removal (S2), renderer
v1 → v2 fixture (S3), rename (S4), races with queued and in-flight renders.

## App unit tests (own simulator "PRE2 iPhone 17", iOS 27.2)

```bash
xcodegen generate
xcodebuild build-for-testing -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,name=PRE2 iPhone 17" \
  -derivedDataPath .autonomous/derived-data-pre-002 CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/PresetThumbnailInvalidationAppTests \
  -only-testing:projectM-iOSTests/PresetThumbnailModelTests
```

Expect: saving an edit to a user preset removes its old thumbnail file and changes the row's request
identity; the other user preset's and the built-in preset's thumbnails stay; removing a user preset
removes its file; the launch collection removes an entry for a preset no longer listed.

## Repo checks

`check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`,
`check_status_events.py`, `test_scripts.py`.
