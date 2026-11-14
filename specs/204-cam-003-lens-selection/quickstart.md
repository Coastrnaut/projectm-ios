# Quickstart: CAM-003

1. `swift test --package-path Packages/Compositor --filter CameraLens` (host).
2. App tests on "CAM3 iPhone 17": `-only-testing:projectM-iOSTests/CameraLensTests` and
   `-only-testing:projectM-iOSUITests/CameraLensUITests`.
3. Stand-in launch arguments (DEBUG): `-uitestCamera granted -uitestCameraLenses wide,ultraWide,telephoto
   -uitestCameraLensFails telephoto`.
4. Device (D1, last): Settings › Visual › Camera, Back, Lens Ultra Wide ↔ Wide ten times; the picture
   follows, the badge stays, no crash. D2/D3: no Lens row.
