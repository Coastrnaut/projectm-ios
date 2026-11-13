# Quickstart: FILE-001 Portable Scene Archive

## Package (Mac host and Linux shape)

```bash
swift test --package-path Packages/SceneArchive
swift test --package-path Packages/SceneArchive -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/LocalPortability
```

Expected: round trip, hostile table, remapping and source-safety tests pass in seconds.

## App service (iOS 27.2 simulator)

```bash
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS -destination "id=<FILE1 sim>" \
  -only-testing:projectM-iOSTests/SceneArchiveServiceTests -only-testing:projectM-iOSTests/PhotoStoreTests \
  -only-testing:projectM-iOSTests/VideoStoreTests CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

Expected: the clean-install round trip resolves every asset, the photo and video decode, hostile
archives and the last-asset failure leave the stores unchanged.

## Device (`{device}`, owner)

Export on D1 (needs the SCN-014 entry point or a DEBUG build calling the service), send by AirDrop or
Files to D3, import there offline; the scene's photo and video appear. Open until the entry point exists.
