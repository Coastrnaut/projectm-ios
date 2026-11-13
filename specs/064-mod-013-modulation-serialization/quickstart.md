# Quickstart: MOD-013 validation

Run from the repository (or the feature worktree) root. No simulator or device is needed (no app code
changes).

```bash
swift test --package-path Packages/ParameterGraph            # migration table and registry checks
swift test --package-path Packages/SceneFormat               # restore, report, fixed point
swift test --package-path Packages/VisualGenerators          # catalog still builds with its table
# Linux shape (as CI's Linux job compiles):
for p in ParameterGraph SceneFormat VisualGenerators; do
  swift test --package-path Packages/$p -Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL \
    -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path Packages/$p/.build/linuxshape
done
python3 scripts/validate_docs.py && python3 scripts/check_compliance.py
```

Expected:

- `ModulationIDMigrationTests`: chaining, idempotence, loop/self/duplicate/cross-kind refusals,
  catalog checks pass.
- `SceneModulationRestoreTests.testEveryCategoryIsReportedWithItsPath`: one document with restored,
  rewritten (twice-renamed), dropped, orphaned target, orphaned source, expression and loop edges;
  the report lists exactly those outcomes and paths; the scene opens.
- `testRestoredEdgesEvaluateLikeTheOriginal`: 64 frames, fixed clock, bit-identical values.
- `SceneModulationPropertyTests`: 200 seeded documents reach a fixed point after one capture; every
  preserved edge survives; under 1 s.
