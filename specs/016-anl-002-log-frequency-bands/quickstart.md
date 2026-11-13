# Quickstart: validating ANL-002

All checks run on the Mac host and the iOS Simulator; no device is needed for this row's acceptance.

## 1. Package tests (host)

```bash
swift test --package-path Packages/AnalysisFeatures
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE   # Linux build shape
swift test --package-path Packages/AnalysisFeatures --filter BandAcceptanceTests        # the matrix only
```

Expected: all pass. `BandAcceptanceTests` prints the acceptance matrix (`ANL-002 matrix:` lines:
tone, band count, size, rate, expected band, measured band, value/A, strict or not) and the largest
"far band" ratio; silence reads exactly 0 everywhere; whole loops repeat bit for bit; with vDSP
available the two paths agree within `1e-5·max + 1e-7`.

## 2. Simulator

```bash
cd Packages/AnalysisFeatures && xcodebuild test -scheme AnalysisFeatures \
  -destination 'id=62BA098B-4CBB-4DB6-91AD-51494936CF89' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/anl002-sim.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" ../../.build/scratch/anl002-sim.log
```

Afterwards count new `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` files (owner rule 5) and
shut the simulator down.

## 3. Bench (reported, not asserted)

```bash
swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench
```

Prints ns per band reduction for every band count at 2,048 and 8,192 points, both backends.

## 4. Repository gates

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && python3 scripts/test_scripts.py
grep -rn AnalysisFeatures project.yml RendererLab.yml Apps Packages/ProjectMBridge Packages/Rendering Packages/ANGLERendering   # expect nothing
```
