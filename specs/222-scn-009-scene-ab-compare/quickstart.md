# Quickstart: SCN-009 Scene A/B Compare

Prerequisites: `xcodegen generate`; presets submodules; `Build` xcframeworks. Simulator "SCN9 iPhone 17" (iOS 27.2).

1. Acceptance (S1-S4): `xcodebuild test-without-building ... -only-testing:projectM-iOSTests/SceneCompareAcceptanceTests` — 20 toggles leave `current.scene`, `current.scene.bak`, the snapshot list and the undo stack unchanged; Cancel restores; Keep B writes once with one undo step; a fresh coordinator on the same folder during Compare restores the pre-Compare scene.
2. UI (S6): `-only-testing:projectM-iOSUITests/SceneCompareUITests` — save two snapshots, start Compare, switch A/B, Keep A, the intensity slider shows A's value.
3. Manual (optional): Settings › Visual › Save Snapshot twice with different glow, Compare A/B…, Start Compare, tap A/B, Done → Cancel Compare.

Simulator results are never device evidence (Constitution X).
