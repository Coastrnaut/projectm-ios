# Quickstart: FX-004 Hue Shift

1. Reference (Linux shape): `swift test --package-path Packages/Compositor -Xswiftc -DCOMPOSITOR_NO_METAL
   -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --filter 'HueShiftReferenceTests|ColorGradeReferenceTests'`.
2. GPU acceptance: `swift test --package-path Packages/Compositor --filter 'HueShift|ColorGrade|CompositeFlashGuard'`
   — grey ramp neutral at 30/90/180/−120°, red patch at 0/120/240° matches research FX-004-D6, hue 0 equals
   FX-003, the guard engages with a shift.
3. Regressions: RenderGoldens and LibraryBackup package tests.
4. App: on an own simulator, `-only-testing:projectM-iOSTests` and
   `-only-testing:projectM-iOSUITests/ColorGradeUITests`.
5. Device (`{device}`): on D1, Photo visual, set Hue +120: reds turn green, greys and white unchanged; reset →
   identical to before; frame rate unchanged in the performance overlay.
