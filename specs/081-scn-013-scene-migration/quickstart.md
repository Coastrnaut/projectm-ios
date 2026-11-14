# Quickstart: SCN-013 Scene Migration

```bash
# SceneFormat: migration chain, golden legacy fixtures (host, then Linux shape)
swift test --package-path Packages/SceneFormat
swift test --package-path Packages/SceneFormat -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE

# ShowStorage backups
swift test --package-path Packages/ShowControl --filter ShowStoreMigrationBackupTests

# App autosave backups (own simulator)
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination 'platform=iOS Simulator,name=SCN13 iPhone 17' \
  -only-testing:projectM-iOSTests/SceneAutosaveMigrationTests CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180
```

## Adding a format version later (procedure, ADR-0028 amendment)

1. Raise `SceneDocument.currentVersion` to N+1 and append a `SceneMigrationStep(fromVersion: N, …)`
   to `SceneMigrator.standard` that records every change.
2. Copy the writer's current output into `Fixtures/legacy/v<N>/` for each real shape, add manifest
   rows, regenerate the `expected/` documents through the new step and review the diff.
3. `SceneLegacyFixtureTests` and QA-004 then cover the new version.
