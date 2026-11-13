# Quickstart: validating SHD-011

All checks run on the Mac host (and the importer tests also in the Linux shape); no simulator or
device is needed (no app code changes).

```bash
python3 scripts/check_compliance.py            # expect "check_compliance: OK"
python3 scripts/test_scripts.py                # every script test passes, new SHD-011 rule tests included
python3 scripts/validate_docs.py               # ADR-0024 and spec references resolve
swift test --package-path Packages/Compositor --filter GeneratorGraphImportTests
swift test --package-path Packages/Compositor --filter GeneratorGraphImportTests \
  -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/Compositor --filter GeneratorGraphTests   # SHD-002 unchanged
```

Expected: the fixture table of [contracts/graph-import.md](contracts/graph-import.md) matches row
for row; the source scan finds no loader, file, bundle, network or shader API in the importer; the
suite runs in well under 10 s.
