# Quickstart: validating ANL-004

All checks run on the Mac host and the iOS Simulator; no device is needed for this row's acceptance.

## 1. Package tests (host)

```bash
swift test --package-path Packages/AnalysisFeatures
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE   # Linux build shape
swift test --package-path Packages/AnalysisFeatures --filter OnsetAcceptanceTests       # the matrix only
```

Expected: all pass. `OnsetAcceptanceTests` prints `ANL-004 matrix:` lines (fixture, rate, size,
hop: onsets, events, misses, false events, largest |error| in samples) for every pulse
combination; silence and below-floor noise give 0 events and a detection value of exactly 0;
every sine and sweep gives exactly 1 event at the start; repeated runs are identical; with vDSP
available both paths give identical events.

## 2. Simulator

```bash
cd Packages/AnalysisFeatures && xcodebuild test -scheme AnalysisFeatures \
  -destination 'id=62BA098B-4CBB-4DB6-91AD-51494936CF89' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/anl004-sim.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" ../../.build/scratch/anl004-sim.log
```

Afterwards count new `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` files (owner rule 5) and
shut the simulator down.

## 3. Bench (reported, not asserted)

```bash
swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench
```

Prints ns per onset `process` call at 2,048 and 8,192 points, both backends.

## 4. Repository gates

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && python3 scripts/test_scripts.py
grep -rn AnalysisFeatures project.yml RendererLab.yml Apps Packages/ProjectMBridge Packages/Rendering Packages/ANGLERendering   # expect nothing
```
