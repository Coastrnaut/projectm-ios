# Quickstart: CAM-008 Person Silhouette Mask

## Automated (Mac)

```bash
swift test --package-path Packages/Compositor --filter PersonMask
xcodegen generate
# app unit + UI tests on the feature's simulator (stand-in camera, fixture segmenter)
```

## Device (D1, `{device}` CAM-008-T16)

1. Install a Debug build on D1; choose the Camera visual; allow the camera.
2. Settings › Camera › Person mask › Person. Stand in view: only you are drawn, over black.
3. Choose Background: you are cut out. Turn the device, switch camera, mirror and Fit/zoom: the mask
   stays aligned.
4. Watch the performance overlay: at or above 30 fps.
5. Record the result (and whether the mask was upright-aligned) in
   `docs/test-reports/camera-person-mask.md`.
