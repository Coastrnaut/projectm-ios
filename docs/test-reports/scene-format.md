# Test report: SCN-001 Versioned scene format

Feature: `specs/059-scn-001-versioned-scene-format` (ADR-0028). Host: the Mac Studio (Xcode 27.2,
Swift 6.4.2), 2026-11-13. No app code changed, so no simulator or device run was needed or made.

## Acceptance

"Decode and re-encode preserve semantic scene content": `SceneRoundTripTests` decodes and
re-encodes the all-kinds fixture (camera, both spectra, photo, video, text, material, generator
graph and an unknown future kind; composite settings and transforms; parameters of every value
kind; bindings with mapping, envelope, mix and an expression; a modulation generator and
connection; every asset type; unknown fields at every extensible level): the documents are equal
under contract C3 and the canonical bytes are identical. `ScenePropertyTests` does the same for 500
seeded random scenes (0 failures).

## Runs

| Run | Result | Time |
|---|---|---|
| `swift test` in `Packages/SceneFormat` (host) | 31/31 pass | 0.60 s tests |
| Linux shape (`--scratch-path .build/linuxshape -DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) | 31/31 pass | 0.55 s tests, 12 s wall with build |
| 500-scene property test | pass | 0.47 s |
| `swift test` in `Packages/Compositor` (host, after the LayerStack amendment) | 185/185 pass | 4.0 s tests, 14 s wall |
| Compositor Linux shape, `--filter LayerStack` | 10/10 pass | < 0.01 s |
| `xcodebuild -scheme SceneFormat -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` | succeeded | 8 s |
| `check_compliance.py`, `validate_docs.py`, `test_scripts.py` | OK, OK, 111 tests OK (1 skipped) | |

Suites: `SceneJSONTests` 7, `SceneRoundTripTests` 5, `ScenePropertyTests` 1, `SceneLiveAdapterTests` 4,
`SceneDecodeErrorTests` 4 (26 refusals with exact messages, 7 count limits at and over their limit,
the 1 MiB boundary, decode warnings), `SceneValidationTests` 6 (every issue code with exact path and
message), `SceneForwardCompatibilityTests` 2, `SceneSourceSafetyTests` 2.

## Not verified here

- A real Linux host (CI's `host-tests-linux` job runs it; the Linux shape on the Mac compiles the
  same code paths).
- The iOS simulator test run of the package (CI's `build-and-test-apple` and `build-ios27` jobs).
- ParameterGraph was not changed, so its tests were not rerun.
