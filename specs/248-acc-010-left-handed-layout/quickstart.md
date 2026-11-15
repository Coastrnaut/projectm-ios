# Quickstart: ACC-010 Left-Handed Layout

## Automated (Mac)

1. `swift test --package-path Packages/ShowControl --filter HandedPlacementTests` — mirror invariants (contract C1).
2. App unit tests (`-only-testing:projectM-iOSTests/LeftHandedAppTests`, `LibraryBackupAppTests`) on a private iOS 27.2 iPhone 17 simulator — preference, key lists, output isolation.
3. UI tests (`-only-testing:projectM-iOSUITests/LeftHandedUITests`) on the same simulator — switching in Settings, mirrored frames, identical identifiers.

Simulator results are UI evidence only.

## Device ({device}, D1 and D2)

1. Settings → Performance → Left-handed controls on. Close Settings.
2. Portrait, pad off, output live: the emergency Black out button is at the bottom left.
3. Controls → Performance layout: Black out at the left end of the bar, Tap tempo next to it, cue arrows on the right (Previous left of Next).
4. Rotate to landscape: Tap tempo and Black out in the left column, cue arrows in the right.
5. Connect an external display: its picture is not mirrored; the device visual is not mirrored.
6. Turn the switch off: everything returns to its right-handed place.
