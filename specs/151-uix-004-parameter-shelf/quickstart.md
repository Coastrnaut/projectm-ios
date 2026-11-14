# Quickstart: UIX-004 Favorite Parameter Shelf

1. Unit tests: `xcodebuild test-without-building ... -only-testing:projectM-iOSTests/ParameterShelfTests`
   — three pins survive a rebuild from the same defaults in order; a stored list with an unknown ID and
   garbage shows only the valid pins, the note counts exactly the missing entries, Remove deletes only
   those; order changes; the limit of 8; a shelf write equals a Settings write.
2. UI test (< 30 s): `-only-testing:projectM-iOSUITests/ParameterShelfUITests` — pins Intensity from the
   inspector (`-uitestInspectParameter effect.bloom.intensity`), sees `shelf.effect.bloom.intensity` in the
   controls, moves it, relaunches without the reset flag and finds it still pinned.
3. Manual (simulator): Settings › Circular Spectrum › Glow on › long press Intensity › Pin to Shelf › Done:
   the slider sits above the control buttons.
