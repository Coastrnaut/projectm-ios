# Quickstart: UIX-007 Split Preview/Editor

## Mac (simulator)

```bash
swift test --package-path Packages/ShowControl --filter SplitEditorLayoutTests
xcodegen generate
# build-for-testing on an iPad simulator (iOS 27.2), then:
#   -only-testing:projectM-iOSTests/SplitEditorSettingTests
#   -only-testing:projectM-iOSUITests/SplitEditorUITests
```

Expected: the layout sweep passes (aspect within 1e-6, rect inside pane); on the iPad simulator
Settings opens beside the output, a divider drag changes the output's on-screen width and keeps its
aspect within 1%.

## Device (D2, iPad Pro M5) `{device}`

1. Play a preset, rotate to landscape, open Settings: the output stays visible on the left.
2. Drag the divider through its range: the picture never stretches; release near 320/400/480 snaps.
3. Settings › Layers: change a layer's opacity; the change is visible live.
4. Rotate to portrait: the split stays, the output is pillar/letterboxed, undistorted.
5. VoiceOver: focus "Editor width", swipe up/down: snaps step.
