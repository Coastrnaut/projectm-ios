# Quickstart: SHOW-009 Keyframe Easing

## Package (host, < 1 min)

```bash
swift test --package-path Packages/ShowControl --filter 'ShowKeyframe'
```

Expected: `ShowKeyframeEasingTests` and `ShowKeyframeTrackTests` pass (contract E1-E6).

## App (simulator "SHOW9 iPhone 17", iOS 27.2)

Build for testing, then run `-only-testing:projectM-iOSTests/ShowKeyframeEasingAcceptanceTests`
`-only-testing:projectM-iOSTests/ShowKeyframeAcceptanceTests` and
`-only-testing:projectM-iOSUITests/ShowKeyframeEasingUITests` (E7, E8; UI test < 30 s).

## Device (D1, `{device}`)

Settings → Show → Keyframe Tracks: a Glow Intensity track with four Cubic keys and one Hold key; play the show on the
projector; the glow flows through the Cubic keys without stopping and cuts at the Hold key.
