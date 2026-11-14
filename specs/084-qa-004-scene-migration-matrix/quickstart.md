# Quickstart: QA-004 Scene Migration Matrix

Run from the repository root. Budgets: each suite under 1 minute (owner rule 7).

```bash
L="-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE"
swift test --package-path Packages/SceneFormat --filter SceneMigrationMatrix      # decode, repairReport, meta
swift test --package-path Packages/ShowControl --filter ShowStoreMigrationMatrix  # showStore
swift test --package-path Packages/SceneArchive --filter SceneArchiveMigrationMatrix  # archive
swift test --package-path Packages/RenderGoldens --filter GoldenMigrationMatrix   # golden (harness on macOS)
swift test --package-path Packages/SceneFormat $L    # Linux shape; likewise the other three
```

Autosave cells (app target), on a dedicated simulator, never the Simulator panel tool:

```bash
xcrun simctl create "QA4 iPhone 17" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodegen generate
xcodebuild test -project ProjectM-iOS.xcodeproj -scheme projectM-iOS \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath .autonomous/derived-data-qa-004 \
  -only-testing:projectM-iOSTests/SceneAutosaveMigrationMatrixTests CODE_SIGNING_ALLOWED=NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 > qa4-app.log 2>&1
xcrun simctl delete <udid>
```

Expected: every runner reports the number of cells it ran (matching the matrix) and passes; the meta
test passes and its "broken copy" checks fail as designed.

Adding a format version: follow the checklist in ADR-0028's QA-004 amendment.
