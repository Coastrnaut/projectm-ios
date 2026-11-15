# Quickstart: CAM-009 Face Landmark Emitters

## Mac (host and simulator)

```bash
swift test --package-path Packages/ParameterGraph --filter FaceFeatureTrackerTests
# Linux shape of the package
swift test --package-path Packages/ParameterGraph --filter "FaceFeatureTrackerTests|AudioFeatureSourceTests"
# App unit tests and the UI test on the private simulator (build-for-testing, then test-without-building):
#   -only-testing:projectM-iOSTests/FaceTrackingAppTests
#   -only-testing:projectM-iOSUITests/FaceTrackingConsentUITests
python3 scripts/check_compliance.py && scripts/check_network_symbols <built .app>
```

Expected: the gate test reports 0 detector creations and 0 detections before consent, more than 0 after, and a flat
count after switching off; the container snapshot is unchanged; the UI test shows the sheet and Cancel leaves the
switch off.

## Device `{device}` (CAM-009-T16, D1)

1. Choose the Camera visual, Front camera. Settings › Camera › Face tracking: on; read the sheet; confirm.
2. The badge reads "Front camera on · Face tracking"; iOS's camera indicator shows.
3. Bind "Mouth open" (DEBUG seed) and open/close the mouth: the value follows within about 0.2 s.
4. The frame rate stays within 5 % of the rate with Face tracking off (performance overlay, 30 s each).
