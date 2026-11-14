# Quickstart: REC-002 Image Batch Export

Simulator "REC2 iPhone 17" (iOS 27.2). Simulator results are never device evidence (Constitution X).

1. `xcodegen generate`, then `xcodebuild build-for-testing` for scheme `projectM-iOS` (see AGENT_RULES options).
2. Unit and acceptance: `-only-testing:projectM-iOSTests/SnapshotBatchNamingTests -only-testing:projectM-iOSTests/SnapshotBatchExportAcceptanceTests`. Expect: five fixture snapshots → exactly five PNGs of 1920 × 1080 named `01-Dawn-Dusk.png`, `02-Dawn-Dusk.png`, `03-Snapshot.png`, `04-Sunset.png`, `05-Snapshot.png`; scene file and backup bytes, snapshot list, undo stack and live values unchanged; cancel leaves no folder.
3. UI: `-only-testing:projectM-iOSUITests/SnapshotBatchExportUITests` (under 30 s): five Save Snapshot taps, Export Images…, Export; the probe lists five files.
4. Manual (optional): Settings › Visual › Export Images… › Export › Save… to a Files folder.
