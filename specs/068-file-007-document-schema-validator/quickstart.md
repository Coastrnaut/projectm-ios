# Quickstart: FILE-007 validation

From the repository root:

```bash
swift test --package-path Packages/LocalPortability      # hostile table, edge cases, fuzz
swift test --package-path Packages/SceneArchive --filter SceneArchiveManifestShapeTests
swift test --package-path Packages/PresetLibrary --filter DocumentShapeTests
swift test --package-path Packages/SceneFormat --filter SceneHostileInputTests
swift test --package-path Packages/Compositor --filter GraphImportHostileInputTests
# Linux shape, per package:
swift test --package-path Packages/<pkg> -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
```

Expected: every hostile case refused with its exact error (contract C1), every importer refuses deep
and oversize input before decoding, existing suites unchanged.
