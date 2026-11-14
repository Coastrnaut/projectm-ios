# Quickstart: SCN-004 Scene Folder Organization

All checks run on the Mac; simulator results are never device evidence.

## Package tests (host; Linux in CI)

```bash
swift test --package-path Packages/ShowControl --filter 'SceneFolder|ShowFolderDocument'
swift test --package-path Packages/LibraryBackup --filter Folder
```

Expected: tree rules (create, rename, move, cycle, depth, collision, delete re-parenting), document
round trip, the legacy fixture (no folder keys) re-encoding byte for byte, damaged data repaired with
warnings, a store reload keeping assignments, and a backup round trip keeping folders.

## App tests (own simulator "SCN4")

```bash
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/SceneFolderAcceptanceTests \
  -only-testing:projectM-iOSTests/SceneSwitcherTests
xcodebuild test-without-building ... -only-testing:projectM-iOSUITests/SceneFoldersUITests
```

Expected: the acceptance test moves a scene from A to B/C and finds its ID and file unchanged, the
cue applies the same scene, the switcher entry resolves with folder path "B / C", and a coordinator
reloaded from the same store keeps the assignment. The UI test (under 30 s) creates a folder, moves
"Opening" into it, opens the folder and sees the scene.

## Manual (optional)

Settings → Show → Scene Folders: New Folder "Set A"; swipe a scene → Move → Set A; open Set A.
