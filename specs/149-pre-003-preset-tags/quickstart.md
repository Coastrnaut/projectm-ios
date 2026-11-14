# Quickstart: PRE-003 Preset Tags

All checks run on the Mac; none needs a device.

1. Packages: `swift test --package-path Packages/PresetLibrary --filter PresetTag` and
   `swift test --package-path Packages/LibraryBackup --filter PresetTag` — rules, index, file, store,
   acceptance (filter → recreate store from disk → same IDs), bundled-file hashes, backup, erase.
2. App unit tests on the "PRE3" simulator: `-only-testing:projectM-iOSTests/PresetTagAcceptanceTests`.
3. UI test: `-only-testing:projectM-iOSUITests/PresetTagsUITests` (seeded tags, chip filter, relaunch,
   same rows; and adding a tag through the sheet), each under 30 s.
4. Repo checks (compliance, docs, motion, permissions, status events, script tests) and the privacy
   manifest and network symbol checks on the Debug app.
5. Optional bench: `PRE003_BENCH=1 swift test --package-path Packages/PresetLibrary --filter PresetTagBench`.
