# Quickstart: PRE-013 Bulk Preset Import

```bash
swift test --package-path Packages/LocalPortability --filter LooseZipReaderTests
swift test --package-path Packages/PresetLibrary --filter BulkImport      # S1-S4 (100-file fixture)
swift test --package-path Packages/ImportFuzz --filter BulkArchiveFuzz
# app: build-for-testing on "PRE13 iPhone 17", then
#   -only-testing:projectM-iOSTests/BulkPresetImportCoordinatorTests
#   -only-testing:projectM-iOSUITests/BulkPresetImportUITests
```

Expected: the folder and zip runs both report added 70, duplicates 15, invalid 8, too large 4,
unsupported 3, failed 0, and the store holds the 5 seeded plus the 70 new presets; a run cancelled after
30 files reports 30 handled and 70 not handled; zip-slip entries are unsupported and nothing appears
outside the store directory. The UI test reads the summary text from the sheet in under 30 s.
Simulator results are not device evidence.
