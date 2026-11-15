# Quickstart: SHOW-007 Timeline Transport

1. Package: `swift test --package-path Packages/ShowControl --filter ShowTimelineTests` (T1, T3, seek plan).
2. App acceptance (simulator "SHOW7 iPhone 17", iOS 27.2): `-only-testing:projectM-iOSTests/ShowTransportAcceptanceTests`
   (T2, T4, T5, T6; SHOW-007-S1 to S3).
3. UI: `-only-testing:projectM-iOSUITests/ShowTimelineUITests` with `-uitestShowSeed -uitestShowTimelineSeed`
   (five cues, 30 s each): adjust the slider to the middle → the cue row reads "Cue 3 of 5" (S4).
4. `{device}` D1: run a timed show, scrub across cues and watch the projector: one look change per release.
