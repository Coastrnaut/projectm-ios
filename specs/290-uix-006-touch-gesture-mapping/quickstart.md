# Quickstart: UIX-006 Touch Gesture Mapping

## Mac (simulator "UIX6 iPhone 17", iOS 27.2)

```bash
swift test --package-path Packages/PerformanceControl --filter GestureShortcut
xcodebuild build-for-testing -scheme projectM-iOS -destination 'platform=iOS Simulator,name=UIX6 iPhone 17' ...
xcodebuild test-without-building ... -only-testing:projectM-iOSTests/GestureShortcutsAppTests \
  -only-testing:projectM-iOSUITests/GestureShortcutsUITests
```

## Device (UIX-006-T14, {device})

1. Settings › Performance › Gesture shortcuts: on. Load a show with three cues.
2. Hide the controls. Two-finger swipe left: next cue, controls stay hidden. Right: previous cue. Up/down: presets.
3. Map Two-finger tap to Tap tempo; tap four times with two fingers at a steady beat: the HUD shows the tapped tempo.
4. One-finger tap still shows and hides the controls without delay.
5. Turn VoiceOver on: two-finger and three-finger gestures do VoiceOver's own actions (pause speech, read all), never a shortcut.
6. Lock the scene: the gestures still work; the Gesture shortcuts section is disabled.
