# Quickstart: MED-008 Animated Image Support

1. `swift test --package-path Packages/Compositor --filter Animated` — model, import and GPU playback tests
   (fixture loops, large file within budget, Reduce Motion, Reduce flashing).
2. App test on the private simulator: `-only-testing:projectM-iOSTests/AnimatedPhotoAppTests`.
3. `{device}` (D1): import a large animated GIF from Photos, show the Photo visual for one minute with the
   performance overlay; the app's memory in Xcode's gauge stays within about the budget above the still-photo
   baseline, playback is smooth, Reduce Motion holds the first frame.
