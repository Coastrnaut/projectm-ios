# Quickstart: validate ANL-005

From the repository root (Mac host; the Linux shape is the `-DANALYSIS_NO_ACCELERATE` run).

```bash
swift test --package-path Packages/AnalysisFeatures --filter 'Beat'
swift test --package-path Packages/AnalysisFeatures --filter 'Beat' -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/AnalysisFeatures            # whole target, both ways
cd Packages/AnalysisFeatures && xcodebuild test -scheme AnalysisFeatures \
  -destination 'platform=iOS Simulator,id=<iOS 27.2 simulator>' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/anl005-sim.log 2>&1
grep -E ': error: |Executed [0-9]+ tests|\*\* TEST' ../../.build/scratch/anl005-sim.log
python3 scripts/validate_docs.py && python3 scripts/check_compliance.py && python3 scripts/test_scripts.py
```

Expected: every `Beat*` test passes; the log prints one `ANL-005 pulse` line per representative
run (converged tempo, time to converge ≤ 4.0 s, 0 missed and 0 extra beats, largest beat error ≤
hop), `ANL-005 change` (≤ 6.0 s), `ANL-005 silence`/`gap` and `ANL-005 noise` (maximum confidence
< 0.5) lines. Contract: [contracts/beat-tracker.md](contracts/beat-tracker.md); entities:
[data-model.md](data-model.md).
