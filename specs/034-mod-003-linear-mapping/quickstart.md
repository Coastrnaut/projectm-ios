# Quickstart: validating MOD-003 Linear Mapping

Prerequisites: the project Mac (Swift 6.4.2); no simulator or device.

1. Acceptance, bounds, monotonicity, clamping, regression:
   `swift test --package-path Packages/ParameterGraph --filter LinearMappingTests`
   Expected: every test passes; each well under 1 s.
2. MOD-002 unchanged: `swift test --package-path Packages/ParameterGraph` (all suites, including
   `AudioFeatureModulatorTests` and `AudioFeatureBindingValidationTests`, unmodified).
3. App catalog: `swift test --package-path Packages/VisualGenerators` and the Linux shape
   `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape`.
4. Rules: `python3 scripts/check_compliance.py` and `python3 scripts/validate_docs.py`.

See [contracts/linear-mapping.md](contracts/linear-mapping.md) for what each test checks.
