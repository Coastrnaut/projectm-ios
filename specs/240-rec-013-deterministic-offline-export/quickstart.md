# Quickstart: REC-013 Deterministic Offline Export

1. Package: `swift test --package-path Packages/VisualGenerators --filter OfflineExport` (clock, source, driver determinism, fixture, manifest).
2. App acceptance on simulator "REC13 iPhone 17": `-only-testing:projectM-iOSTests/OfflineExportAcceptanceTests` — two 2 s exports at 30 fps, 160 × 90, identical checksums, 60 frames in the MP4 with an audio track, seed and audio changes alter the list, cancel leaves no folder.
3. UI: `-only-testing:projectM-iOSUITests/OfflineExportUITests` — opens the sheet, exports 1 s of the fixture (`-uitestOfflineExportSeconds 1`), sees "Exported 30 frames".
4. Device `{device}` (D1): export the fixture twice at Landscape 30 fps, compare the two sidecars' `frameChecksums`, and note the render time.
