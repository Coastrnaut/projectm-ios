# Quickstart: CAM-006 Camera White Balance

1. Package tests (Mac host): `swift test --package-path Packages/Compositor --filter CameraWhiteBalanceTests`
   — lock/unlock, unsupported (0 configurations), invalid gains fuzz (0 invalid applied), interruption
   keeps the lock, switch/stop release it.
2. App tests on the "CAM6 iPhone 17" simulator (iOS 27.2): `-only-testing:projectM-iOSTests/CameraWhiteBalanceAppTests`.
3. UI test: `-only-testing:projectM-iOSUITests/CameraWhiteBalanceUITests` (stand-in camera,
   `-uitestCamera granted`, `-uitestCameraWhiteBalanceLock none` for the unsupported case).
4. Device (`{device}`, CAM-006-T09): on D1, Camera visual under colored light: lock → colors hold;
   interrupt (a call or Siri) and return → still locked; switch lens → switch off, automatic again.
   Simulator results are never device evidence.
