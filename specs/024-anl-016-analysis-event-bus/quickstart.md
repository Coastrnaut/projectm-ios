# Quickstart: ANL-016 Analysis Event Bus

Validation runs on the Mac host and a simulator; no device is needed.

## Host

```bash
swift test --package-path Packages/AudioCore --filter AnalysisSession
swift test --package-path Packages/AnalysisFeatures --filter "AnalysisPipelineTests|AnalysisSubscriptionTests"
swift test --package-path Packages/AnalysisFeatures                                   # whole suite (< ~45 s)
swift test --package-path Packages/AnalysisFeatures -Xswiftc -DANALYSIS_NO_ACCELERATE
swift test --package-path Packages/VisualGenerators --filter "BandFeedTests|LiveBandAnalyzerTests"
swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
```

Expected: every test passes; each bus test prints its counts (frames read, onsets, beats, IDs,
drops) and takes about 1–2 s or less.

## Simulator

From `Packages/AnalysisFeatures`:

```bash
xcodebuild test -scheme AnalysisFeatures -destination 'id=6ABB17A2-D4EB-4B42-B5FF-E7C39E89637A' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO \
  > ../../.build/scratch/anl016-sim.log 2>&1
grep -E ": error: |Executed [0-9]+ tests|\*\* TEST" ../../.build/scratch/anl016-sim.log
```

## Scenarios covered (spec user stories)

1. Ordered frames and onset/beat events with strictly increasing IDs (US1, ANL-016-S1).
2. Capture restart, source switch, detach/attach, straddling chunk: no repeated ID, no stale item (US2, S2).
3. Slow subscriber: drop-oldest with counts; a second subscriber receives everything (US3, S3).
4. Unsubscribe; deterministic replays (US4, S4, S5).
5. Circular spectrum on the bus: VIS-001 band-feed tests (US5, S6).

Optional `{device}`: run the app's Circular Spectrum on D1 with music and confirm the bars move as
before (not required for acceptance).
