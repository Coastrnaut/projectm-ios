# Quickstart: validating ANL-001

All checks run on the Mac host and the iOS Simulator; no device is needed for this row's acceptance.

## 1. Package tests (host)

```bash
swift test --package-path Packages/AnalysisFeatures
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE   # Linux build shape
swift test --package-path Packages/AudioCore
swift test --package-path Packages/AudioCore -Xswiftc -DAUDIOCORE_NO_AVFAUDIO
```

Expected: all pass. The acceptance suite (`FixtureAcceptanceTests`) covers every sine fixture ×
5 sizes × 2 rates (documented bin on the first window, within one bin on every frame of the loop),
the sweeps (finite, peaks near the documented instantaneous frequency at 2,048), repeated runs
bit-identical, silence exactly 0, the amplitude scale, both backends against each other and the
reference DFT.

## 2. Simulator

```bash
cd Packages/AnalysisFeatures && xcodebuild test -scheme AnalysisFeatures \
  -destination 'id=62BA098B-4CBB-4DB6-91AD-51494936CF89' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/anl001-sim.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" ../../.build/scratch/anl001-sim.log
```

## 3. Dependents unchanged (AudioCore tap added)

```bash
for p in CaptureKit CaptureUI Diagnostics; do swift test --package-path Packages/$p; done
```

## 4. CPU per frame (reported, never asserted)

```bash
swift run -c release --package-path Packages/AnalysisFeatures/Bench AnalysisBench
```

Prints, per size and backend, nanoseconds per frame and the share of one core at the default hop
(44.1 kHz), plus the streaming path at 2,048. Allocation check: run the bench with
`MallocStackLoggingNoCompact=1 <bench> --loop-seconds 8` and, while it runs,
`malloc_history <pid> -allEvents`; no ALLOC or FREE event has `magnitudes(of`, `rawMagnitudes`,
`nextFrame` or `append(` in its stack. (Instruments could not attach to the bench on the build Mac,
2026-11-13.)

## 5. Repository gates

```bash
python3 scripts/check_compliance.py && python3 scripts/validate_docs.py && python3 scripts/test_scripts.py
```
