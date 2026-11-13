# Quickstart: MOD-014 Modulation Feedback Prevention

Run from the repository root (or the feature worktree):

```bash
swift test --package-path Packages/ParameterGraph --filter ModulationGraph   # MOD-014 tests
swift test --package-path Packages/ParameterGraph                            # whole package, incl. MOD-002/003
swift test --package-path Packages/VisualGenerators                          # catalog bindings
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL \
  -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape          # Linux build shape
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py
```

Expected: all pass. `testAcceptanceCycleFixtureFailsWithReadablePath` asserts the path
`macro.a → visual.ring.gap → lfo.one.rate → macro.a` exactly ([contract](contracts/modulation-graph.md) G5).
No simulator or device step: no app code changes.
