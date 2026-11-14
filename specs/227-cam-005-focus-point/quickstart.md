# Quickstart: CAM-005 Camera Focus Point

1. Package: `swift test --package-path Packages/Compositor --filter CameraFocusTests` — mapping table,
   seam and stand-in provider (< 1 s).
2. App unit tests: `-only-testing:projectM-iOSTests/CameraFocusAppTests` on "CAM5 iPhone 17".
3. UI: `-only-testing:projectM-iOSUITests/CameraFocusUITests` — stand-in camera, double-tap sets the
   probed point; unsupported camera shows the explanation.
4. Device (T14, D1): Camera visual, back wide lens; double-tap a near object → it sharpens and the ring
   shows; Fit + double-tap a bar → nothing; front camera with mirror → focus follows the finger.
