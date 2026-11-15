# Quickstart: SHOW-008 Keyframe Tracks

1. Package: `swift test --package-path Packages/ShowControl --filter ShowKeyframe` (K1 to K4; SHOW-008-S1, S2, S4).
2. App acceptance (simulator "SHOW8 iPhone 17", iOS 27.2): `-only-testing:projectM-iOSTests/ShowKeyframeAcceptanceTests`
   (K5, K6; SHOW-008-S3).
3. UI: `-only-testing:projectM-iOSUITests/ShowKeyframeUITests` with `-uitestShowSeed -uitestShowTimelineSeed`: open
   Settings → Show → Keyframe Tracks…, add Glow Intensity, Add Keyframe at Playhead → a row "0:00, …" (S5).
4. `{device}` D1: a glow ramp across two cues on the projector; scrub to a keyframe and see its value.
